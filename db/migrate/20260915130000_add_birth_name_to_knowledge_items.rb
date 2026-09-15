# #1615 (Hans): „Bei Personen den Geburtsnamen als Feld anzeigen. Oder würde
# man das über einen Alias lösen? Genauer wäre Geburtsname."
#
# Eigenes Feld statt Alias: Ein Alias sagt nicht, WAS der andere Name ist.
# Damit die Person trotzdem unter ihrem Geburtsnamen gefunden wird wie unter
# einem Alias, fliesst das Feld mit demselben Gewicht (A) in den Suchvektor.
class AddBirthNameToKnowledgeItems < ActiveRecord::Migration[8.1]
  def up
    add_column :knowledge_items, :birth_name, :string, null: true

    execute <<~SQL
      CREATE OR REPLACE FUNCTION knowledge_items_search_vector_update() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          setweight(to_tsvector('german', coalesce(NEW.title, '')), 'A') ||
          setweight(to_tsvector('german', coalesce(array_to_string(NEW.aliases, ' '), '')), 'A') ||
          setweight(to_tsvector('german', coalesce(NEW.birth_name, '')), 'A') ||
          setweight(to_tsvector('german', coalesce(array_to_string(NEW.tags, ' '), '')), 'B') ||
          setweight(to_tsvector('german', coalesce(NEW.body, '')), 'C');
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute "DROP TRIGGER IF EXISTS knowledge_items_search_vector_trigger ON knowledge_items"
    execute <<~SQL
      CREATE TRIGGER knowledge_items_search_vector_trigger
        BEFORE INSERT OR UPDATE OF title, aliases, tags, body, birth_name ON knowledge_items
        FOR EACH ROW EXECUTE FUNCTION knowledge_items_search_vector_update();
    SQL
    # Kein Anstupsen des Bestands nötig: die neue Spalte ist überall leer.
  end

  def down
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

    execute "DROP TRIGGER IF EXISTS knowledge_items_search_vector_trigger ON knowledge_items"
    execute <<~SQL
      CREATE TRIGGER knowledge_items_search_vector_trigger
        BEFORE INSERT OR UPDATE OF title, aliases, tags, body ON knowledge_items
        FOR EACH ROW EXECUTE FUNCTION knowledge_items_search_vector_update();
    SQL

    remove_column :knowledge_items, :birth_name
  end
end
