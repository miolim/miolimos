# #183: Verknüpft einen `[[Title|URL]]`-Wikilink in einer Quell-KI mit
# dem Researcher-Task, der die Ziel-KI erzeugen soll, und (sobald
# angelegt) der Ziel-KI selbst. Render-Pfad nutzt Existenz + Status, um
# pro Wikilink 🔍 / ⏳ / nichts (=fertig) zu zeigen.
class WikilinkResearchJob < ApplicationRecord
  belongs_to :source_knowledge_item,
             class_name: "KnowledgeItem",
             foreign_key: :source_knowledge_item_id,
             primary_key: :uuid
  belongs_to :target_knowledge_item,
             class_name: "KnowledgeItem",
             foreign_key: :target_knowledge_item_id,
             primary_key: :uuid,
             optional: true
  belongs_to :task

  validates :target_title, presence: true
  validates :source_knowledge_item_id,
            uniqueness: { scope: :target_title }

  scope :pending, -> { where(target_knowledge_item_id: nil) }
  scope :done,    -> { where.not(target_knowledge_item_id: nil) }

  def done?
    target_knowledge_item_id.present?
  end
end
