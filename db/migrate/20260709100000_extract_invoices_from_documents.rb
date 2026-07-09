# #926 (Hans, 2026-07-09): Document war zur Sammel-Entität geworden (Brief,
# NDA, Rechnung, Angebot, Lastschrift in einer Tabelle). Neues Zielbild:
# Dokumenterstellung ist ein VERFAHREN, das auf strukturierte Entitäten
# angewendet wird — die Rechnung (inkl. Angebot) wird eine eigene Entität,
# Document schrumpft auf das Anschreiben (Brief/NDA/SEPA-Mandat).
# Felder + festgeschriebene PDF-Stände werden polymorph (EINE Artefakt-
# Schicht für alle druckbaren Entitäten). Alte Rechnungs-/Angebots-
# Dokumente werden entsorgt statt migriert (Hans-OK in #926: Bestand
# unwichtig, kein Verlustrisiko).
class ExtractInvoicesFromDocuments < ActiveRecord::Migration[8.0]
  def up
    # ── 1) Rechnung/Angebot als eigene Entität ────────────────────────────
    create_table :invoices do |t|
      t.integer :kind,   null: false, default: 0   # rechnung/angebot
      t.integer :status, null: false, default: 0   # entwurf/final
      t.string  :issuer_uuid
      t.string  :recipient_uuid
      t.bigint  :recipient_address_id
      t.bigint  :topic_id
      t.bigint  :creator_id
      t.string  :subject
      t.string  :number
      t.date    :document_date
      t.date    :service_start
      t.date    :service_end
      t.string  :your_ref
      t.string  :our_ref
      t.integer :shown_identifier_ids, array: true, default: []
      t.string  :theme, default: "din5008_b"
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :invoices, :issuer_uuid
    add_index :invoices, :recipient_uuid
    add_index :invoices, :topic_id
    add_index :invoices, :deleted_at
    add_foreign_key :invoices, :postal_addresses, column: :recipient_address_id
    add_foreign_key :invoices, :topics
    add_foreign_key :invoices, :actors, column: :creator_id

    # ── 2) Alt-Daten entsorgen (Rechnungs-/Angebots-Dokumente + Positionen) ─
    execute "UPDATE time_entries SET invoice_line_id = NULL WHERE invoice_line_id IS NOT NULL"
    execute "DELETE FROM invoice_lines"
    execute "DELETE FROM document_fields    WHERE document_id IN (SELECT id FROM documents WHERE kind IN (2,3))"
    execute "DELETE FROM document_artifacts WHERE document_id IN (SELECT id FROM documents WHERE kind IN (2,3))"
    execute "DELETE FROM documents WHERE kind IN (2,3)"

    # ── 3) Positionen hängen an der Rechnung (Tabelle ist ab hier leer) ────
    remove_column :invoice_lines, :document_id
    add_reference :invoice_lines, :invoice, null: false, foreign_key: true

    # ── 4) Felder + Artefakte polymorph (eine Schicht für alle Entitäten) ──
    add_column :document_fields, :fieldable_type, :string
    add_column :document_fields, :fieldable_id, :bigint
    execute "UPDATE document_fields SET fieldable_type = 'Document', fieldable_id = document_id"
    change_column_null :document_fields, :fieldable_type, false
    change_column_null :document_fields, :fieldable_id, false
    add_index :document_fields, [:fieldable_type, :fieldable_id]
    remove_column :document_fields, :document_id

    add_column :document_artifacts, :printable_type, :string
    add_column :document_artifacts, :printable_id, :bigint
    execute "UPDATE document_artifacts SET printable_type = 'Document', printable_id = document_id"
    change_column_null :document_artifacts, :printable_type, false
    change_column_null :document_artifacts, :printable_id, false
    add_index :document_artifacts, [:printable_type, :printable_id]
    remove_column :document_artifacts, :document_id

    # ── 5) Document aufs Anschreiben eindampfen ────────────────────────────
    remove_column :documents, :number
    remove_column :documents, :service_start
    remove_column :documents, :service_end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
