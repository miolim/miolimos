# #155 Phase 5c: Join Source ↔ Topic mit Relevanz-Markierung.
# #575 (Hans, 2026-06-10): zwei Dimensionen statt Dreier-Enum —
#   relevance: relevant | irrelevant   (inhaltliches Urteil)
#   reached:   true | false            (Zugriff auf die Quelle)
# Der alte dritte Wert "unreached" wird aus Kompatibilität (API,
# Researcher-Workflows) weiter angenommen und auf
# relevance=relevant + reached=false abgebildet.
class SourceTopic < ApplicationRecord
  RELEVANCES = %w[relevant irrelevant].freeze

  belongs_to :source
  belongs_to :topic

  validates :source_id, uniqueness: { scope: :topic_id }
  validates :relevance, inclusion: { in: RELEVANCES }

  scope :relevant,   -> { where(relevance: "relevant") }
  scope :irrelevant, -> { where(relevance: "irrelevant") }
  scope :unreached,  -> { where(reached: false) }

  def relevance=(val)
    if val.to_s == "unreached"
      self.reached = false
      super("relevant")
    else
      super
    end
  end
end
