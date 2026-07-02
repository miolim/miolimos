# #532 (Hans, 2026-06-08): Document-Datenmodell. Ein Dokument ist ein
# Kompositions-Objekt: referenziert Aussteller/Empfänger (Person/Org-KIs),
# optional einen Prosa-Body (KI) und ein Topic (Projekt); Rechnungen tragen
# strukturierte Positionen (invoice_lines, EN16931-tauglich, siehe #541).
class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.integer :kind,          null: false, default: 0   # brief/nda/rechnung/angebot
      t.integer :status,        null: false, default: 0   # entwurf/final
      t.string  :issuer_uuid                              # KnowledgeItem.uuid (Aussteller)
      t.string  :recipient_uuid                           # KnowledgeItem.uuid (Empfänger)
      t.string  :body_ki_uuid                             # KnowledgeItem.uuid (Prosa-Body)
      t.bigint  :topic_id                                 # Projekt
      t.bigint  :creator_id                               # Actor
      t.string  :subject
      t.string  :salutation                              # Override; leer = aus Empfänger
      t.string  :number                                  # Rechnungs-/Dokumentnummer
      t.date    :document_date
      t.string  :theme,         null: false, default: "din5008_b"
      t.timestamps
    end
    add_index :documents, :issuer_uuid
    add_index :documents, :recipient_uuid
    add_index :documents, :body_ki_uuid
    add_index :documents, :topic_id
    add_index :documents, [:kind, :status]

    create_table :invoice_lines do |t|
      t.references :document, null: false, foreign_key: true
      t.integer  :position,    null: false, default: 0
      t.string   :description
      t.string   :unit                                   # h, Stk, Pauschal …
      t.decimal  :quantity,   precision: 12, scale: 2, null: false, default: 0
      t.decimal  :unit_price, precision: 12, scale: 2, null: false, default: 0
      t.decimal  :tax_rate,   precision: 5,  scale: 2, null: false, default: 19
      t.timestamps
    end
  end
end
