# #387 Phase A.3 (Hans, 2026-05-28): Eine Zeile pro Color-Highlight-
# Anker — bindet eine 8-Hex-ID an die KI, in deren Body sie steht.
# Daten kommen aus dem KnowledgeItem-Save-Hook (siehe
# KnowledgeItemAnchors::Sync). Wikilink-Resolver nutzt diese Tabelle
# fuer `[[^anchorid]]` → KI-UUID.
class KnowledgeItemAnchor < ApplicationRecord
  # #466 (Hans, 2026-06-02): zwei Anker-Formate erlaubt — 8-Hex fuer
  # Color-Highlights (SecureRandom.hex(4)) und 6-stellig alphanumerisch
  # fuer Block-Anker (SecureRandom.alphanumeric(6), via ensure_anchor).
  # Beide muessen indizierbar sein, damit `[[^anker]]` global aufloest.
  validates :anchor, presence: true, uniqueness: true,
                     format: { with: /\A(?:[a-f0-9]{8}|[a-z0-9]{6})\z/ }
  validates :knowledge_item_uuid, presence: true
end
