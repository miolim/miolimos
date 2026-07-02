# #541 (Hans, 2026-06-08): USt-Befreiung (z.B. Kleinunternehmer §19 UStG) am
# ausstellenden Kontakt. Reine DB-Spalte (Source of Truth = DB, kein
# Frontmatter), davon abhängig zeigt die Rechnung das MwSt-Feld an — oder nicht.
class AddVatExemptToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :vat_exempt, :boolean, default: false, null: false
  end
end
