# #786 (Hans): Bankverbindung eines Person-/Org-KI (mehrere möglich). DB ist
# Source of Truth (DB-direkt editiert, keine Frontmatter-Sync) — wie
# PostalAddress (#532). Quelle u.a. fürs SEPA-Lastschriftmandat (Schuldner).
class BankAccount < ApplicationRecord
  belongs_to :knowledge_item, class_name: "KnowledgeItem",
             foreign_key: :knowledge_item_uuid, primary_key: :uuid

  scope :ordered, -> { order(:position, :id) }

  # IBAN/BIC normalisiert speichern (ohne Leerzeichen, Großbuchstaben).
  before_save do
    self.iban = iban.to_s.gsub(/\s+/, "").upcase.presence
    self.bic  = bic.to_s.gsub(/\s+/, "").upcase.presence
  end

  def blank? = [iban, bic, bank_name, holder].all?(&:blank?)

  # IBAN in 4er-Gruppen für die Anzeige.
  def iban_pretty = iban.to_s.gsub(/(.{4})/, '\1 ').strip

  # Anzeige-Label: eigenes Label, sonst Bank, sonst IBAN.
  def display_label = label.presence || bank_name.presence || iban_pretty.presence || "—"

  def oneline
    [holder.presence, iban_pretty.presence, bic.presence, bank_name.presence].compact_blank.join(" · ")
  end
end
