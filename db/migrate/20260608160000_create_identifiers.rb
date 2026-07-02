# #544 (Hans, 2026-06-08): ID-Nummern als getypte Key-Value-Sätze am
# Person/Org-KI. Optional mit Gegenseite (counterparty) — die Org/Person, die
# die Nummer vergibt (Kundennummer bei X). DB ist Source of Truth (#241).
class CreateIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :identifiers do |t|
      t.string  :knowledge_item_uuid, null: false   # Inhaber (Person/Org-KI)
      t.string  :counterparty_uuid                  # optional: vergebende Gegenseite
      t.string  :label,    null: false              # Typ, z.B. Kundennummer
      t.string  :value,    null: false              # die Nummer
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :identifiers, :knowledge_item_uuid
    add_index :identifiers, :counterparty_uuid
  end
end
