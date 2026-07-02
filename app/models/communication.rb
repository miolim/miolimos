class Communication < ApplicationRecord
  # #602 S1: Kommunikation hat keinen creator — Sichtbarkeit über die
  # Topic-Zuordnung. #602 S2 ("je Nutzer sein Konto"): zusätzlich sieht
  # der INHABER des OAuth-Kontos die Mails seines Postfachs auch ohne
  # Topic-Zuordnung — der Scope unten ÜBERSCHREIBT dafür den von
  # visible_via erzeugten (der Write-Guard bleibt vom Concern).
  include VisibleVia
  visible_via join: "CommunicationTopic", join_fk: :communication_id,
              owner_columns: []

  scope :visible_to, ->(actor) {
    next all  if actor&.visibility_exempt?
    next none if actor.nil?
    visible_topics = Topic.visible_to(actor).select(:id)
    where(id: CommunicationTopic.where(topic_id: visible_topics).select(:communication_id))
      .or(where(oauth_credential_id: OauthCredential.where(actor_id: actor.id).select(:id)))
  }

  # #602 S2: Konto-Inhaber darf seine Mails auch bearbeiten/löschen
  # (z.B. Topic-Zuordnung, lokales Löschen) — sonst gilt die Topic-Regel.
  def writable_by?(actor)
    return true if actor && oauth_credential_id.present? &&
                   oauth_credential&.actor_id == actor.id
    super
  end

  belongs_to :oauth_credential, optional: true

  has_many :communication_topics, dependent: :destroy
  has_many :topics, through: :communication_topics

  has_many :communication_mentions, dependent: :destroy
  has_many :mentioned_kis, through: :communication_mentions, source: :mentioned

  has_many :tasks, dependent: :nullify

  has_many :awaitings, dependent: :nullify

  # #765: verknüpftes Kalender-Event (dokumentierte Anrufe). Beim Löschen der
  # Kommunikation wird der Event-Verweis genullt (Event bleibt im Kalender).
  has_one :event, dependent: :nullify

  belongs_to :suggested_topic, class_name: "Topic", optional: true

  enum :direction, { inbound: 0, outbound: 1 }, default: :inbound

  validates :external_id, presence: true, uniqueness: true
  validates :type,        presence: true

  # #695 (Hans): Tags (string[]-Spalte) <-> zentrale Tag/Tagging-Registry
  # synchron halten — analog Task/KnowledgeItem.
  after_save    :sync_taggings, if: :saved_change_to_tags?
  after_destroy :remove_taggings
  def sync_taggings  = TagSync.sync_communication(self)
  def remove_taggings = Tagging.where(taggable_type: "Communication", taggable_id_int: id).delete_all

  scope :inbound,  -> { where(direction: :inbound) }
  scope :outbound, -> { where(direction: :outbound) }

  # Ungelesen nur für eingehende Mails — selbst-geschriebene sind per se
  # "gesehen". Wird beim ersten Öffnen der Detail-View auf Time.current
  # gesetzt (siehe CommunicationsController#show).
  scope :unread, -> { inbound.where(read_at: nil) }

  def unread?
    inbound? && read_at.nil?
  end

  def mark_read!
    return unless unread?
    update_column(:read_at, Time.current)
  end

  scope :for_account, ->(email) {
    joins(:oauth_credential).where(oauth_credentials: { email_address: email })
  }

  # Teilnehmer einer Rolle: kombiniert verlinkte Person/Org-KIs (mit Namen)
  # und rohe E-Mail-Adressen aus `participants` (Gmail-Sync), die noch
  # keinem KI zugeordnet sind. Rückgabe: Array von Hashes mit entweder
  # :ki oder :email gesetzt.
  def participants_for(role)
    role_str = role.to_s
    linked = communication_mentions.includes(:mentioned)
                                    .select { |cm| cm.role.to_s == role_str }
                                    .map(&:mentioned)
                                    .compact
    result     = linked.map { |k| { ki: k } }
    seen_uuids = linked.map(&:uuid).to_set

    raw = Array(participants[role_str]).map(&:to_s).reject(&:blank?)
    return result if raw.empty?

    # #697 (Hans): rohe Teilnehmer-Adressen LIVE gegen die E-Mail-
    # Kontaktpunkte der Person/Org-KIs auflösen — so erscheint der
    # Kontaktname auch, wenn die Adresse erst nachträglich am Kontakt
    # hinterlegt wurde (vorher griff nur die beim Sync gesetzte Mention,
    # also blieb die Adresse roh). Doppel-Anzeige (Mention + Adresse
    # desselben KI) wird über seen_uuids vermieden.
    ki_by_email = ContactPoint.where(kind: "email")
                              .where("LOWER(value) IN (?)", raw.map(&:downcase).uniq)
                              .eager_load(:knowledge_item)
                              .where(knowledge_items: { item_type: %w[person organization] })
                              .index_by { |cp| cp.value.to_s.downcase }

    raw.each do |addr|
      ki = ki_by_email[addr.downcase]&.knowledge_item
      if ki
        next if seen_uuids.include?(ki.uuid)
        seen_uuids << ki.uuid
        result << { ki: ki }
      else
        result << { email: addr }
      end
    end
    result
  end

  # #633: Anhänge aus der gespeicherten Gmail-Message (raw_data hält die
  # komplette payload-Struktur — kein Re-Sync nötig). Liefert
  # [{filename:, mime_type:, size:, attachment_id:}, …]; Inline-Parts
  # ohne Dateinamen (Body-Text, eingebettete Bilder ohne Namen) fallen
  # raus. Schlüssel können je nach Serialisierung snake_case oder
  # camelCase sein — beides abdecken.
  def attachments
    walk_attachment_parts(raw_data["payload"] || raw_data[:payload] || {})
  end

  private

  def walk_attachment_parts(part, acc = [])
    return acc unless part.is_a?(Hash)
    body     = part["body"] || part[:body] || {}
    filename = (part["filename"] || part[:filename]).to_s
    att_id   = body["attachment_id"] || body["attachmentId"]
    if filename.present? && att_id.present?
      acc << { filename:      filename,
               mime_type:     (part["mime_type"] || part["mimeType"]).to_s,
               size:          (body["size"] || 0).to_i,
               attachment_id: att_id.to_s }
    end
    Array(part["parts"] || part[:parts]).each { |child| walk_attachment_parts(child, acc) }
    acc
  end
end
