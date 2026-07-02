# #536: Portal-Zugang — verknüpft eine Kunden-E-Mail mit GENAU EINEM
# Projekt-Topic. Die Isolations-Grenze des Portals: jede Portal-Query läuft
# über den Zugang der Session, nie über freie Parameter.
#
# Magic-Links sind zustandslos: ein signierter, zweckgebundener Token
# (MessageVerifier) mit Ablauf — nichts zu speichern, Widerruf über
# `active: false` (Session-Lookup prüft active bei jedem Request).
class PortalAccess < ApplicationRecord
  MAGIC_LINK_TTL  = 15.minutes
  SESSION_TTL     = 14.days
  VERIFIER_PURPOSE = "portal_magic_link".freeze

  # #619 Stufe 3: UI-Sprache je Zugang (nil = Default-Locale).
  LOCALES = %w[de en].freeze
  validates :locale, inclusion: { in: LOCALES }, allow_blank: true

  belongs_to :topic
  belongs_to :customer_ki, class_name: "KnowledgeItem",
    foreign_key: :knowledge_item_uuid, primary_key: :uuid, optional: true

  validates :email, presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP, message: "ist keine gültige E-Mail" },
    uniqueness: { scope: :topic_id }

  normalizes :email, with: ->(e) { e.strip.downcase }

  scope :active, -> { where(active: true) }

  def self.verifier
    Rails.application.message_verifier(VERIFIER_PURPOSE)
  end

  # Signierter Login-Token für die Mail (läuft nach MAGIC_LINK_TTL ab).
  def magic_token
    self.class.verifier.generate({ id: id }, expires_in: MAGIC_LINK_TTL, purpose: :login)
  end

  # Token → aktiver Zugang oder nil (abgelaufen/manipuliert/deaktiviert).
  def self.from_magic_token(token)
    data = verifier.verified(token.to_s, purpose: :login)
    return nil unless data
    active.find_by(id: data["id"] || data[:id])
  end

  # Session-Token (eigenes Cookie, getrennt von der internen Session).
  def session_token
    self.class.verifier.generate({ id: id }, expires_in: SESSION_TTL, purpose: :session)
  end

  def self.from_session_token(token)
    return nil if token.blank?
    data = verifier.verified(token.to_s, purpose: :session)
    return nil unless data
    active.find_by(id: data["id"] || data[:id])
  end
end
