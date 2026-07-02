# #695 (Hans): Kommunikationen taggbar machen (bisher nur Topic-Zuordnung).
# string[]-Spalte wie bei Task/KnowledgeItem; ein after_save-Hook synct sie
# in die zentrale Tag/Tagging-Registry.
class AddTagsToCommunications < ActiveRecord::Migration[8.1]
  def change
    add_column :communications, :tags, :string, array: true, default: [], null: false
  end
end
