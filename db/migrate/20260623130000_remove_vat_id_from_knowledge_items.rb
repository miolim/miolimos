# #761 (Hans, 2026-06-23): Die alte vat_id-Spalte entfernen. Die USt-IdNr wohnt
# seit #544 als Identifier im IDs-Bereich; alle Bestandswerte wurden dorthin
# migriert. Das Feld führte sonst zu Doppelpflege/Verwirrung.
class RemoveVatIdFromKnowledgeItems < ActiveRecord::Migration[8.1]
  def up
    remove_column :knowledge_items, :vat_id
  end

  def down
    add_column :knowledge_items, :vat_id, :string
  end
end
