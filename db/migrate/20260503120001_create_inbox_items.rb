class CreateInboxItems < ActiveRecord::Migration[8.1]
  def change
    create_table :inbox_items do |t|
      # Wo kommt das Item her — bestimmt mit `payload` zusammen, was
      # die Processors damit anfangen können.
      # source_kind: youtube_url | web_url | markdown | text | upload
      t.string :source_kind, null: false

      t.string :source_url               # für url-basierte Items
      t.text   :raw_content              # für markdown/text-Items
      t.string :external_path            # absoluter Pfad bei Folder-Watch-Imports
      t.string :title                    # vom User editierbar / aus URL extrahiert
      t.jsonb  :payload, null: false, default: {}  # source_kind-spezifische Metadaten

      # status: pending → processing → processed / failed (User kann
      # auch direkt auf archived setzen, ohne Verarbeitung).
      t.string :status, null: false, default: "pending"

      # Welcher Processor wurde gewählt / verwendet?
      t.string :processor_kind

      # Provenance: wenn Verarbeitung KIs/Tasks erzeugt hat, hier per
      # JSONB-Liste festhalten — die KIs selbst zeigen via inbox_item_id
      # zurück.
      t.jsonb  :result, null: false, default: {}

      # Fehlerdetails wenn status=failed.
      t.text     :error_message
      t.datetime :processed_at

      t.references :creator, null: false, foreign_key: { to_table: :actors }

      t.timestamps
    end

    add_index :inbox_items, :status
    add_index :inbox_items, :source_kind
    add_index :inbox_items, :created_at
  end
end
