# #532 Phase 2 (Hans, 2026-06-07): Stammdaten-Fundament. Markiert ein
# Person/Org-KI als "Aussteller" (eigenes Rechtssubjekt), aus dem Hans
# Rechnungen ausstellt — als natürliche Person UND/ODER über die Firma.
# Mehrere Aussteller sind erlaubt. vat_id (USt-IdNr) existiert bereits.
class AddIssuerToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :issuer, :boolean, default: false, null: false
    add_index  :knowledge_items, :issuer, where: "issuer", name: "index_knowledge_items_on_issuer"
  end
end
