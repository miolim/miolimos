class AddSearchVectorToKnowledgeItemsAndTasks < ActiveRecord::Migration[8.1]
  def up
    # ─── KIs: body + tsvector ──────────────────────────────────────────────
    add_column :knowledge_items, :body, :text
    add_column :knowledge_items, :search_vector, :tsvector
    add_index  :knowledge_items, :search_vector,
               using: :gin, name: "idx_kis_search_vector"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION knowledge_items_search_vector_update() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          setweight(to_tsvector('german', coalesce(NEW.title, '')), 'A') ||
          setweight(to_tsvector('german', coalesce(array_to_string(NEW.aliases, ' '), '')), 'A') ||
          setweight(to_tsvector('german', coalesce(array_to_string(NEW.tags, ' '), '')), 'B') ||
          setweight(to_tsvector('german', coalesce(NEW.body, '')), 'C');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER knowledge_items_search_vector_trigger
        BEFORE INSERT OR UPDATE OF title, aliases, tags, body ON knowledge_items
        FOR EACH ROW EXECUTE FUNCTION knowledge_items_search_vector_update();
    SQL

    # Bestehende Zeilen einmal "anstupsen" damit der Trigger feuert.
    execute "UPDATE knowledge_items SET title = title;"

    # ─── Tasks: tsvector über title + description ──────────────────────────
    add_column :tasks, :search_vector, :tsvector
    add_index  :tasks, :search_vector,
               using: :gin, name: "idx_tasks_search_vector"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION tasks_search_vector_update() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          setweight(to_tsvector('german', coalesce(NEW.title, '')), 'A') ||
          setweight(to_tsvector('german', coalesce(NEW.description, '')), 'C');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER tasks_search_vector_trigger
        BEFORE INSERT OR UPDATE OF title, description ON tasks
        FOR EACH ROW EXECUTE FUNCTION tasks_search_vector_update();
    SQL

    execute "UPDATE tasks SET title = title;"
  end

  def down
    execute "DROP TRIGGER IF EXISTS tasks_search_vector_trigger ON tasks"
    execute "DROP FUNCTION IF EXISTS tasks_search_vector_update()"
    remove_index  :tasks, name: "idx_tasks_search_vector"
    remove_column :tasks, :search_vector

    execute "DROP TRIGGER IF EXISTS knowledge_items_search_vector_trigger ON knowledge_items"
    execute "DROP FUNCTION IF EXISTS knowledge_items_search_vector_update()"
    remove_index  :knowledge_items, name: "idx_kis_search_vector"
    remove_column :knowledge_items, :search_vector
    remove_column :knowledge_items, :body
  end
end
