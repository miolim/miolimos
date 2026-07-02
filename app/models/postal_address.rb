# #532 (Hans, 2026-06-08): strukturierte Postadresse eines Person/Org-KI.
# EN16931: line1/line2 (Adresszeilen), postal_code, city, country. DB ist
# Source of Truth — DB-direkt editiert, keine Frontmatter-Sync.
class PostalAddress < ApplicationRecord
  belongs_to :knowledge_item, class_name: "KnowledgeItem",
             foreign_key: :knowledge_item_uuid, primary_key: :uuid

  # #622: Adresstyp — liegenschaft (Besuchsanschrift, Default) oder
  # post (Versandanschrift, oft Postfach). Briefe/DIN-Fenster nehmen
  # bevorzugt die Postadresse (KnowledgeItem#mailing_address).
  enum :kind, { liegenschaft: 0, post: 1 }, default: :liegenschaft

  scope :ordered, -> { order(:position, :id) }
  scope :billing, -> { where(billing: true) }

  # Adresszeilen fürs DIN-Adressfeld: Straße, (Zusatz), "PLZ Ort", (Land).
  def lines
    [line1, line2, [postal_code, city].compact_blank.join(" ").presence, country]
      .compact_blank
  end

  def oneline = lines.join(" · ")
  def blank?  = lines.empty?
end
