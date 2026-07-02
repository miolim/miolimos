require "base64"
require "google/apis/gmail_v1"
require "signet/oauth_2/client"

# GmailSync – synchronisiert eine Gmail-Mailbox in die Communication-Tabelle.
#
# - Pro OAuth-Credential, nicht pro Actor.
# - Inkrementell wenn last_history_id gesetzt ist, sonst voller Reimport.
# - Dedupliziert über external_id (Gmail Message-ID) – Unique-Index fängt Rennen.
# - Kontakt-Matching gegen Person-KIs (Email-Feld); unbekannte Absender
#   werden automatisch als Person-KI angelegt (Name aus Local-Part der
#   Adresse abgeleitet) und als CommunicationMention verlinkt.
# - Token-Refresh über Signet bei Ablauf oder 401.
class GmailSync
  class SyncError < StandardError; end

  # #574 (Hans): KURATIERTER Sync statt Voll-Import — miolimOS besitzt nur
  # Vorgangs-Kommunikation. Zwei Kanäle:
  #   1. Absender-Allowlist = alle Personen/Org-KIs mit E-Mail-Kontaktpunkt,
  #      ab credential.sync_since (Startdatum, gesetzt beim Verbinden) —
  #      Alt-Bestand fremder Postfächer bleibt draußen.
  #   2. Gmail-Label "miolimOS" = explizite Ad-hoc-Kuration, OHNE Datums-
  #      grenze (so holt man gezielt auch ältere Mails rein).
  # Der Accept-Gate in ingest_message gilt für ALLE Pfade (auch den
  # History-Inkrementalsync) — nichts Unkuratiertes kommt durch.
  SYNC_LABEL = "miolimOS".freeze

  Result = Struct.new(:created, :updated, :skipped, :errors, :deleted, keyword_init: true) do
    def to_s
      "created=#{created} updated=#{updated} skipped=#{skipped} deleted=#{deleted} errors=#{errors}"
    end
  end

  def self.sync(credential, client: nil)
    new(credential, client: client).sync
  end

  def self.full_sync(credential, client: nil)
    new(credential, client: client).full_sync
  end

  def initialize(credential, client: nil)
    @credential = credential
    @client = client
  end

  def sync
    if @credential.last_history_id.blank?
      full_sync
    else
      incremental_sync
    end
  end

  # #574: Erst-/Vollsync ist kuratiert — Label-Query (zeitlos) +
  # Allowlist-Queries (ab sync_since), statt das ganze Postfach zu ziehen.
  def full_sync
    result = Result.new(created: 0, updated: 0, skipped: 0, errors: 0, deleted: 0)

    # Allowlist als Snapshot VOR dem Ingest — der Label-Ingest legt neue
    # Kontakte an, die sonst mitten im Lauf die Query-Menge ändern würden.
    allowlisted_emails

    each_message_id(q: "label:#{SYNC_LABEL}") { |id| ingest_message(id, result) }

    # Gmail-q hat Längen-Grenzen — Allowlist in Häppchen abfragen.
    # #690 (Hans): EIN- UND AUSGEHENDE Mails holen — `from:` allein zog nur
    # Mails VON bekannten Kontakten; Mails, die der Nutzer AN sie geschrieben
    # hat (`to:`), wurden nie geholt (obwohl das Accept-Gate beide Richtungen
    # akzeptiert). Jetzt `(from:(…) OR to:(…))`.
    since = @credential.sync_since
    allowlisted_emails.each_slice(20) do |chunk|
      addrs = chunk.join(" OR ")
      q = "(from:(#{addrs}) OR to:(#{addrs}))"
      q += " after:#{since.strftime("%Y/%m/%d")}" if since
      each_message_id(q: q) { |id| ingest_message(id, result) }
    end

    profile = with_retry { gmail.get_user_profile("me") }
    @credential.update!(last_history_id: profile.history_id.to_s) if profile&.history_id

    result
  end

  private

  # Seitenweise Message-IDs einer Gmail-Suchquery.
  def each_message_id(q:)
    page_token = nil
    loop do
      listing = with_retry { gmail.list_user_messages("me", q: q, page_token: page_token, max_results: 100) }
      Array(listing.messages).each { |stub| yield stub.id }
      page_token = listing.next_page_token
      break unless page_token
    end
  end

  # #574: E-Mail-Adress-/UUID-Paare aller Personen/Orgs (Basis für Allowlist
  # und Inhaber-Erkennung).
  def person_org_email_pairs
    @person_org_email_pairs ||= ContactPoint.emails
      .joins(:knowledge_item)
      .where(knowledge_items: { item_type: [:person, :organization] })
      .pluck(:knowledge_item_uuid, :value)
      .map { |uuid, v| [uuid, v.to_s.strip.downcase] }
      .reject { |_uuid, v| v.blank? }
  end

  # #574: alle E-Mail-Adressen bekannter Personen/Orgs (die Allowlist) —
  # #768 (Hans): OHNE die eigenen Adressen des Kontoinhabers. Sonst gilt jede
  # Mail, bei der Hans nur Empfänger ist, als Vorgangs-Mail (er steht ja mit
  # all seinen Adressen als Kontakt drin) → es wird ALLES importiert.
  def allowlisted_emails
    @allowlisted_emails ||= begin
      own = own_addresses
      person_org_email_pairs.map { |_uuid, v| v }.reject { |v| own.include?(v) }.uniq
    end
  end

  # #768 v2 (Hans): eigene ("interne") Adressen — zählen NIE als Allowlist-
  # Treffer, nur Mails mit einem ANDEREN bekannten Beteiligten werden importiert.
  # Selbst-Identität explizit über Actor#person_ki ("Das bin ich"); die
  # Postfach-Überschneidung bleibt Fallback für Konten ohne gesetzte Selbst-KI.
  # Policy (Setting.sync_exclude_internal_team?):
  #   - true  (Default): alle verbundenen Konten + deren Selbst-KIs = intern
  #                      (interner Team-Verkehr bleibt draußen).
  #   - false: nur der Inhaber DIESES Sync-Kontos ist „ich"
  #            (interner Team-Verkehr wird importiert).
  def own_addresses
    @own_addresses ||= begin
      if Setting.sync_exclude_internal_team?
        mailboxes = OauthCredential.pluck(:email_address)
        actors    = Actor.where.not(person_ki_uuid: nil).to_a
      else
        mailboxes = [@credential.email_address]
        actors    = [@credential.actor].compact
      end
      mailboxes = (mailboxes + [@credential.email_address])
                    .map { |v| v.to_s.strip.downcase }.reject(&:blank?).uniq

      explicit_emails = actors.flat_map(&:self_email_addresses)

      # Fallback: KIs, deren Adresse mit einem eigenen Postfach übereinstimmt,
      # samt aller ihrer Adressen (greift, solange „Das bin ich" nicht gesetzt).
      heuristic_uuids  = person_org_email_pairs.select { |_u, v| mailboxes.include?(v) }.map(&:first).uniq
      heuristic_emails = person_org_email_pairs.select { |u, _v| heuristic_uuids.include?(u) }.map(&:last)

      (mailboxes + explicit_emails + heuristic_emails).uniq.to_set
    end
  end

  # #574: Accept-Gate — Label "miolimOS" ODER ein Beteiligter (Absender wie
  # Empfänger) ist bekannter Kontakt. Eigene Adressen des Inhabers sind aus der
  # Allowlist ausgenommen (#768), zählen also nie als Treffer. So zählen ein-
  # UND ausgehende Mails mit bekannten Kontakten als Vorgangs-Mail, eine Mail
  # nur an den Inhaber selbst aber nicht.
  def accepted?(message, parsed)
    label_ids = Array(message.label_ids).map(&:to_s)
    return true if sync_label_id && label_ids.include?(sync_label_id)
    participants = (parsed[:participants] || {}).values.flatten
                     .map { |a| a.to_s.strip.downcase }
                     .reject { |a| a.blank? || own_addresses.include?(a) }
    participants.any? { |addr| allowlisted_emails.include?(addr) }
  end

  # Die ID des Kurations-Labels (Name → ID, einmal pro Lauf). nil, wenn das
  # Label im Postfach (noch) nicht existiert.
  def sync_label_id
    return @sync_label_id if defined?(@sync_label_id)
    labels = with_retry { gmail.list_user_labels("me") }
    @sync_label_id = Array(labels.labels).find { |l| l.name == SYNC_LABEL }&.id
  rescue Google::Apis::Error => e
    Rails.logger.warn("GmailSync: labels nicht lesbar (#{e.message})")
    @sync_label_id = nil
  end

  def incremental_sync
    result = Result.new(created: 0, updated: 0, skipped: 0, errors: 0, deleted: 0)
    page_token = nil
    latest_history_id = @credential.last_history_id

    loop do
      history = with_retry do
        gmail.list_user_histories("me",
          start_history_id: @credential.last_history_id,
          page_token: page_token,
          # messageDeleted feuert bei hartem Löschen; labelAdded fängt das
          # Verschieben in den Papierkorb (TRASH-Label).
          history_types: %w[messageAdded messageDeleted labelAdded])
      end

      (history.history || []).each do |h|
        latest_history_id = h.id.to_s if h.id

        (h.messages_added || []).each do |added|
          ingest_message(added.message.id, result)
        end

        (h.messages_deleted || []).each do |removed|
          prune_message(removed.message.id, result)
        end

        (h.labels_added || []).each do |event|
          label_ids = Array(event.label_ids).map(&:to_s)
          next unless label_ids.include?("TRASH")
          prune_message(event.message.id, result)
        end
      end

      page_token = history.next_page_token
      break unless page_token
    end

    @credential.update!(last_history_id: latest_history_id) if latest_history_id.present?

    result
  rescue Google::Apis::ClientError => e
    # 404 with "history" means last_history_id is too old — fall back to full_sync
    if e.message.to_s.match?(/history|not found/i)
      Rails.logger.warn("GmailSync: history_id stale, falling back to full_sync (#{e.message})")
      full_sync
    else
      raise
    end
  end

  # Hartes Löschen einer bereits synchronisierten Mail, weil sie in Gmail
  # gelöscht oder in den Papierkorb verschoben wurde. Task.communication_id
  # und Awaiting.communication_id sind dependent: :nullify — referenzierende
  # Records bleiben erhalten, der Backlink geht auf nil.
  def prune_message(message_id, result)
    comm = Communication.find_by(external_id: message_id)
    return unless comm
    comm.destroy!
    result.deleted += 1
  rescue => e
    Rails.logger.error("GmailSync: failed to prune #{message_id}: #{e.class} #{e.message}")
    result.errors += 1
  end

  def ingest_message(message_id, result)
    if Communication.exists?(external_id: message_id)
      result.skipped += 1
      return
    end

    message = with_retry { gmail.get_user_message("me", message_id, format: "full") }
    parsed  = MessageParser.parse(message, account_email: @credential.email_address)

    # #574: Kurations-Gate — gilt für Voll- UND History-Sync.
    unless accepted?(message, parsed)
      result.skipped += 1
      return
    end

    comm = nil
    ActiveRecord::Base.transaction do
      comm = Email.create!(
        subject:             parsed[:subject],
        body:                parsed[:body],
        sent_at:             parsed[:sent_at],
        direction:           parsed[:direction],
        external_id:         message_id,
        oauth_credential:    @credential,
        raw_data:            parsed[:raw],
        participants:        parsed[:participants].transform_keys(&:to_s)
      )

      link_contacts(comm, parsed[:participants])
      assign_projects(comm)
    end

    # Phase 6a: Nach der Aufnahme sofort klassifizieren. Fällt still
    # durch, wenn Ollama nicht erreichbar ist.
    if comm
      begin
        Classifiers::EmailTopicSuggester.new.apply(comm)
      rescue => e
        Rails.logger.warn("GmailSync: classifier failed on #{comm.external_id}: #{e.class} #{e.message}")
      end
    end

    result.created += 1
  rescue ActiveRecord::RecordNotUnique
    # race with a concurrent sync — not an error
    result.skipped += 1
  rescue => e
    Rails.logger.error("GmailSync: failed to ingest #{message_id}: #{e.class} #{e.message}")
    result.errors += 1
  end

  # Person-KI je Teilnehmer-Adresse anlegen (oder finden) und als
  # CommunicationMention verlinken. Vorheriger Bug: unbekannte Absender
  # wurden nur geloggt, nicht angelegt — jetzt: auto-create.
  def link_contacts(comm, participants)
    actor = sync_actor
    participants.each do |role, emails|
      Array(emails).each do |addr|
        ki = PersonKiResolver.find_or_create_by_email!(addr, actor: actor)
        next unless ki
        # #794 (Hans): idempotenter Garant — der verlinkte Teilnehmer trägt
        # SEINE Adresse als E-Mail-Kontaktpunkt. find_or_create_by_email!
        # hängt sie beim Anlegen an; falls das je nicht durchschlägt, zieht
        # dieser Schritt sie beim (nächsten) Sync sicher nach. Attach-only,
        # bestehende Kontaktpunkte bleiben erhalten → keine Duplikate.
        ensure_email_contact!(ki, addr, actor)
        CommunicationMention.find_or_create_by!(
          communication: comm, mentioned_uuid: ki.uuid, role: role.to_s
        )
      end
    end
  end

  # #794: hängt addr als E-Mail-Kontaktpunkt an ki, falls noch nicht da.
  def ensure_email_contact!(ki, addr, actor)
    addr = addr.to_s.strip.downcase
    return if addr.empty?
    return if ki.contact_points.where(kind: "email").where("lower(value) = ?", addr).exists?
    existing = ki.contact_points.map { |c| { "kind" => c.kind, "label" => c.label.to_s, "value" => c.value.to_s } }
    FileProxy.update(actor: actor, knowledge_item: ki,
                     contact_points: existing + [{ "kind" => "email", "label" => "", "value" => addr }])
  end

  # #574 K2: ist ein Beteiligter Kunde eines Projekts, hängt die Mail
  # automatisch am Projekt (CommunicationTopic) — Projektkorrespondenz
  # sortiert sich selbst ein.
  def assign_projects(comm)
    uuids = comm.communication_mentions.pluck(:mentioned_uuid)
    return if uuids.empty?
    Topic.projects.where(customer_uuid: uuids).find_each do |project|
      CommunicationTopic.find_or_create_by!(communication: comm, topic: project)
    end
  end

  def sync_actor
    @sync_actor ||= HumanActor.order(:id).first ||
      raise(SyncError, "GmailSync needs a HumanActor for auto-creating Person-KIs")
  end

  # #633: Anhang-Bytes einer Message holen (users.messages.attachments.get).
  # Klassen-Seam, damit Tests/Aufrufer nicht den Client-Aufbau kennen müssen
  # (Instanz-Methode liegt im private-Bereich → send).
  def self.fetch_attachment(credential, message_id, attachment_id)
    new(credential).send(:fetch_attachment, message_id, attachment_id)
  end

  def fetch_attachment(message_id, attachment_id)
    att = with_retry { gmail.get_user_message_attachment("me", message_id, attachment_id) }
    MessageParser.decode(att.data.to_s)
  end

  def gmail
    @gmail ||= build_client
  end

  def build_client
    return @client if @client

    refresh_token_if_needed!
    svc = Google::Apis::GmailV1::GmailService.new
    svc.authorization = signet_client
    svc
  end

  def signet_client
    Signet::OAuth2::Client.new(
      client_id:       google_oauth_client_id,
      client_secret:   google_oauth_client_secret,
      token_credential_uri: "https://oauth2.googleapis.com/token",
      refresh_token:   @credential.refresh_token,
      access_token:    @credential.access_token,
      expires_at:      @credential.expires_at
    )
  end

  def refresh_token_if_needed!
    return unless @credential.expired?

    client = signet_client
    begin
      client.refresh!
    rescue Signet::AuthorizationError, Google::Apis::AuthorizationError => e
      # #760 (Hans, 2026-06-23): Refresh-Token tot — abgelaufen oder
      # widerrufen (`invalid_grant`). Bei Google-OAuth im Testing-Modus
      # passiert das systematisch nach 7 Tagen (#687). Das Konto
      # deaktivieren, damit der 15-Minuten-Job (GmailSyncJob) nicht weiter
      # ins Leere läuft, und statt der kryptischen Signet-Meldung eine
      # klare, handlungsleitende Fehlermeldung werfen.
      @credential.update!(active: false) if @credential.active?
      raise SyncError,
            "Verbindung zu #{@credential.email_address} ist abgelaufen oder wurde widerrufen — " \
            "bitte das Konto unter Einstellungen → Konten neu verbinden. (#{e.message})"
    end
    @credential.update!(
      access_token: client.access_token,
      expires_at:   Time.at(client.expires_at.to_i)
    )
  end

  def with_retry(max: 1)
    attempts = 0
    begin
      yield
    rescue Google::Apis::AuthorizationError, Signet::AuthorizationError => e
      attempts += 1
      if attempts <= max
        @credential.update!(expires_at: 1.minute.ago)
        refresh_token_if_needed!
        @gmail = nil
        retry
      else
        raise SyncError, "Auth failed after refresh: #{e.message}"
      end
    end
  end

  def google_oauth_client_id
    ENV["GOOGLE_OAUTH_CLIENT_ID"] ||
      Rails.application.credentials.dig(:google, :oauth_client_id) ||
      raise(SyncError, "GOOGLE_OAUTH_CLIENT_ID missing")
  end

  def google_oauth_client_secret
    ENV["GOOGLE_OAUTH_CLIENT_SECRET"] ||
      Rails.application.credentials.dig(:google, :oauth_client_secret) ||
      raise(SyncError, "GOOGLE_OAUTH_CLIENT_SECRET missing")
  end

  # ─── Message-Parser ────────────────────────────────────────────────────────
  module MessageParser
    module_function

    def parse(message, account_email:)
      headers = (message.payload&.headers || []).to_h { |h| [h.name.to_s.downcase, h.value.to_s] }

      from = parse_addresses(headers["from"])
      to   = parse_addresses(headers["to"])
      cc   = parse_addresses(headers["cc"])
      bcc  = parse_addresses(headers["bcc"])

      direction =
        if from.any? { |addr| addr.casecmp?(account_email) }
          :outbound
        else
          :inbound
        end

      participants = {
        sender:    from,
        recipient: to,
        cc:        cc,
        bcc:       bcc
      }

      {
        subject:      headers["subject"],
        body:         extract_body(message.payload),
        sent_at:      parse_date(headers["date"]) || Time.at(message.internal_date.to_i / 1000),
        direction:    direction,
        participants: participants,
        raw:          message.respond_to?(:to_h) ? message.to_h : message.as_json
      }
    end

    def parse_addresses(header)
      return [] if header.blank?
      header.scan(/[\w.+-]+@[\w.-]+/).uniq
    end

    def parse_date(value)
      return nil if value.blank?
      Time.parse(value)
    rescue ArgumentError
      nil
    end

    def extract_body(payload)
      return nil unless payload
      text = walk_parts(payload).find { |p| p[:mime_type] == "text/plain" }
      html = walk_parts(payload).find { |p| p[:mime_type] == "text/html" }
      (text || html || {})[:data]
    end

    def walk_parts(part, acc = [])
      if part.body&.data
        acc << { mime_type: part.mime_type, data: decode(part.body.data) }
      end
      (part.parts || []).each { |child| walk_parts(child, acc) }
      acc
    end

    def decode(data)
      Base64.urlsafe_decode64(data)
    rescue ArgumentError
      data.to_s
    end
  end
end
