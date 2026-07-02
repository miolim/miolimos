# #359 (Hans, 2026-05-25): Optionaler Work-Tree-Titel + -Subtitel pro
# Topic. Wird im Rendering-Blade ueber den Knoten gerendert (= das
# „Werk hat einen Titel"). Beide Felder optional — wenn beide leer,
# faellt das Rendering auf den Topic-Namen zurueck.
class AddWorkTreeTitleToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :work_tree_title,    :string
    add_column :topics, :work_tree_subtitle, :string
  end
end
