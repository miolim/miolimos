class Relation < ApplicationRecord
  # #239 Phase A: typed Beziehung zwischen zwei Items (KI/Task/Topic/
  # Source/...). Polymorph an beiden Enden. Wird automatisch erzeugt,
  # wenn im Body-Markdown ein Wikilink mit `^anchor_id`-Anker steht.
  # User-pflegbare Felder: label, description, direction, recognized_*.
  DIRECTIONS = %w[source_to_target undirected bidirectional].freeze
  # #155 Phase 5a: `user_confirmed` ergaenzt — Nutzer-erkannte Beziehung
  # (Hans' „Nutzer-erkannt\"-Stufe der Verbindungstypologie). Standard-
  # Schreibweise: Agent legt Relation an (recognized_role: agent), Nutzer
  # bestaetigt → setzt recognized_role: user_confirmed.
  ROLES      = %w[author_source author_target third_party agent user_confirmed].freeze

  belongs_to :recognized_by, class_name: "Actor", optional: true

  validates :anchor_id,   presence: true, length: { is: 6 },
                          format: { with: /\A[0-9a-z]{6}\z/ }
  validates :source_uuid, presence: true
  validates :source_type, presence: true
  validates :target_uuid, presence: true
  validates :target_type, presence: true
  validates :anchor_id,   uniqueness: { scope: :source_uuid }
  validates :direction,   inclusion: { in: DIRECTIONS }
  validates :recognized_role, inclusion: { in: ROLES, allow_nil: true }

  scope :active,   -> { where(orphaned_at: nil) }
  scope :orphaned, -> { where.not(orphaned_at: nil) }
  scope :for_source, ->(uuid) { where(source_uuid: uuid) }
  scope :for_target, ->(uuid) { where(target_uuid: uuid) }

  # 6-Zeichen base36-Id, kollisionsfrei pro Source-Item. Wir versuchen
  # bis zu 5x; bei 36^6 ≈ 2 Mrd. Kollisions-Wahrscheinlichkeit minimal.
  def self.generate_anchor_id(source_uuid:)
    5.times do
      candidate = SecureRandom.alphanumeric(6).downcase
      next unless candidate =~ /\A[0-9a-z]{6}\z/
      next if where(source_uuid: source_uuid, anchor_id: candidate).exists?
      return candidate
    end
    raise "Konnte keine eindeutige anchor_id finden fuer source=#{source_uuid}"
  end
end
