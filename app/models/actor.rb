class Actor < ApplicationRecord
  include ActorPreferences

  # #768 (Hans): explizite Selbst-Identität ("Das bin ich") — die Person-KI,
  # die diesen Actor als Mensch abbildet. Quelle der eigenen E-Mail-Adressen
  # für den Mail-Sync-Filter (ersetzt die Postfach-Überschneidungs-Heuristik).
  belongs_to :person_ki, class_name: "KnowledgeItem", foreign_key: :person_ki_uuid,
             primary_key: :uuid, optional: true

  # Alle E-Mail-Adressen der verknüpften Selbst-KI (lowercase), [] ohne Link.
  def self_email_addresses
    return [] unless person_ki
    person_ki.contact_points.where(kind: "email")
             .pluck(:value).map { |v| v.to_s.strip.downcase }.reject(&:blank?)
  end

  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships

  # #602 S1: System-Rolle. admin = sieht alles (heutiges Verhalten),
  # member = sieht Mitglieds-Topics + intern Öffentliches + Eigenes,
  # guest = reserviert für S3 (wird bis dahin wie member behandelt).
  enum :role, { admin: 0, member: 1, guest: 2 }, default: :member

  has_many :topic_memberships, dependent: :destroy
  has_many :member_topics, through: :topic_memberships, source: :topic

  # Wer ist von der Sichtbarkeits-Filterung ausgenommen? Admins — und
  # Agenten: die arbeiten themenübergreifend und sind übers Capability-
  # System (WAS) gegated; ihre Topic-Einschränkung ist eine S3-Frage.
  def visibility_exempt?
    admin? || is_a?(AgentActor)
  end

  has_many :capabilities, dependent: :destroy

  has_many :created_topics, class_name: "Topic", foreign_key: :creator_id, dependent: :nullify
  has_many :created_tasks, class_name: "Task", foreign_key: :creator_id, dependent: :nullify
  has_many :assigned_tasks, class_name: "Task", foreign_key: :assignee_id, dependent: :nullify

  has_many :awaitings, foreign_key: :creator_id, dependent: :destroy

  has_many :audit_logs, dependent: :nullify

  # #995: Portokassen-/API-Zugang für die Internetmarke (Einstellungen).
  has_one :internetmarke_credential, dependent: :destroy

  validates :name, presence: true
  validates :type, presence: true

  scope :active, -> { where(active: true) }

  # #384 Phase 2 (Hans, 2026-05-27): Actor-Slug fuer @-Mention-Adressierung.
  # Derived aus name (`Hans Groth` -> `hans-groth`). Eindeutig genug
  # solange Namen sich nicht doppeln (das ist System-Setup-Verantwortung).
  def slug
    name.to_s.parameterize.presence
  end

  # #1052: API-Tokens liegen nur als SHA256-Digest in der DB (wie GitHub-
  # PATs) — hier der eine Hash-Weg für Speichern UND Auth-Lookup.
  def self.digest_api_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # Finder fuer @-Mentions: probiert Slug, dann Email-Local-Part.
  def self.find_by_mention_slug(slug)
    s = slug.to_s.strip.downcase
    return nil if s.empty?
    # 1. Slug ueber parameterize(name) — schmaler Index existiert nicht,
    #    aber Actor-Tabelle ist klein (<100 Eintraege), Linear-Scan ok.
    Actor.active.where("LOWER(name) ~ ?", "^#{Regexp.escape(s.tr('-', ' '))}$").first ||
      Actor.active.where("LOWER(SPLIT_PART(email, '@', 1)) = ?", s).first ||
      Actor.active.find { |a| a.slug == s }
  end
end
