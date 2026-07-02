class SourceCreator < ApplicationRecord
  belongs_to :source
  belongs_to :knowledge_item,
    foreign_key: :knowledge_item_uuid, primary_key: :uuid

  ROLES = %w[author editor translator court reporter
             illustrator director composer interviewer].freeze

  # #516 (Hans, 2026-06-05): Identifizierung der Verknüpfung — die Aussage
  # „diese Person ist Rolleninhaber dieser Quelle". provisional = unbestätigt
  # (Namens-Stub), identified = bestätigt. Konfidenz qualitativ (keine
  # Schein-Prozente); identified_via = worauf gestützt (orcid, name, …).
  IDENTIFICATIONS = %w[provisional identified].freeze
  CONFIDENCES     = %w[vermutet wahrscheinlich bestätigt].freeze

  belongs_to :identified_by, class_name: "Actor", optional: true

  validates :role, inclusion: { in: ROLES }
  validates :knowledge_item_uuid, presence: true
  validates :identification, inclusion: { in: IDENTIFICATIONS }
  validates :confidence, inclusion: { in: CONFIDENCES }, allow_nil: true

  scope :provisional, -> { where(identification: "provisional") }
  scope :identified,  -> { where(identification: "identified") }

  def provisional? = identification == "provisional"
  def identified?  = identification == "identified"

  # Verknüpfung als bestätigt markieren — mit Konfidenz + Provenienz.
  def identify!(confidence: nil, via: nil, by: nil)
    update!(identification: "identified", confidence: confidence,
            identified_via: via, identified_by: by, identified_at: Time.current)
  end
end
