# #532 (Hans, 2026-06-08): zusätzliche freie Key-Value-Felder am Dokument
# (im Informationsblock ausgegeben) + Auswahl, welche ID-Felder (#544) des
# Empfängers angezeigt werden (shown_identifier_ids).
class CreateDocumentFields < ActiveRecord::Migration[8.1]
  def change
    create_table :document_fields do |t|
      t.references :document, null: false, foreign_key: true
      t.string  :label,    null: false
      t.string  :value,    null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_column :documents, :shown_identifier_ids, :integer, array: true, default: [], null: false
  end
end
