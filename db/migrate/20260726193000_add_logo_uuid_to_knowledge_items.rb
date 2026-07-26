# #1168 (Hans): Personen/Organisationen können ein Logo haben — für den
# Briefkopf und andere Dokumente. Das Logo ist ein normales Bild-KI;
# hier lebt nur die Referenz (UUID), analog parent_org_uuid.
class AddLogoUuidToKnowledgeItems < ActiveRecord::Migration[8.0]
  def change
    add_column :knowledge_items, :logo_uuid, :string, null: true
  end
end
