require "test_helper"
require "ostruct"

class GmailSyncTest < ActiveSupport::TestCase
  # ─── Fake Gmail client ──────────────────────────────────────────────────
  # Accepts the same method shapes that GmailSync calls and lets us script
  # the responses from the test.
  class FakeGmailClient
    attr_accessor :messages_pages, :history_pages, :profile, :get_message_handler, :calls

    def initialize
      @messages_pages = []
      @history_pages  = []
      @profile        = Struct.new(:history_id, :email_address).new("12345", "hans@example.com")
      @get_message_handler = nil
      @calls = []
    end

    def list_user_messages(user_id, q: nil, page_token: nil, max_results: 100)
      @calls << [:list_user_messages, user_id, q, page_token, max_results]
      @messages_pages.shift || raise("no more messages pages scripted")
    end

    # #574: Label-Auflösung für das Kurations-Gate.
    attr_accessor :labels
    def list_user_labels(_user_id)
      Struct.new(:labels).new(@labels || [])
    end

    def list_user_histories(user_id, start_history_id:, page_token: nil, history_types: nil)
      @calls << [:list_user_histories, user_id, start_history_id, page_token, history_types]
      @history_pages.shift || raise("no more history pages scripted")
    end

    def get_user_message(user_id, id, format:)
      @calls << [:get_user_message, user_id, id, format]
      raise "no get_user_message handler" unless @get_message_handler
      @get_message_handler.call(id)
    end

    def get_user_profile(_user_id)
      @profile
    end
  end

  # GmailSync.link_contacts ruft PersonKiResolver.find_or_create_by_email!,
  # was wiederum FileProxy.create benutzt — dafür braucht der erste
  # HumanActor in der DB die KI-Capabilities. Der Sync läuft FS-frei,
  # weil FileProxy.create in einer isolierten BASE_PATH operiert.
  setup do
    @sync_actor = create_human(name: "Hans")
    grant(@sync_actor, "KnowledgeItem", %w[read create update delete])

    @tmp_base = Dir.mktmpdir("miolimos-gmail-sync-")
    @prev_base = FileProxy.const_get(:BASE_PATH)
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, Pathname.new(@tmp_base))
    Dir.chdir(@tmp_base) do
      system("git", "init", "-q", "-b", "main")
      system("git", "-c", "user.name=test", "-c", "user.email=test@test.local",
             "commit", "--allow-empty", "-q", "-m", "root")
    end
  end

  teardown do
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @prev_base)
    FileUtils.remove_entry(@tmp_base) if @tmp_base && File.exist?(@tmp_base)
  end

  def build_cred(**overrides)
    OauthCredential.create!({
      actor:         @sync_actor,
      provider:      "google",
      email_address: "hans-#{SecureRandom.hex(4)}@example.com",
      access_token:  "a",
      refresh_token: "r",
      expires_at:    1.hour.from_now,
      scopes:        [],
      last_history_id: nil
    }.merge(overrides))
  end

  def fake_message(id:, subject:, from:, to: "hans@example.com", cc: nil, body_text: "body", date: Time.current, internal_ms: nil, label_ids: [])
    body_part = OpenStruct.new(
      mime_type: "text/plain",
      body: OpenStruct.new(data: Base64.urlsafe_encode64(body_text)),
      parts: nil
    )
    payload = OpenStruct.new(
      mime_type: "multipart/alternative",
      headers: [
        OpenStruct.new(name: "From",    value: from),
        OpenStruct.new(name: "To",      value: to),
        (OpenStruct.new(name: "Cc",      value: cc) if cc),
        OpenStruct.new(name: "Subject", value: subject),
        OpenStruct.new(name: "Date",    value: date.rfc2822)
      ].compact,
      body: OpenStruct.new(data: nil),
      parts: [body_part]
    )
    OpenStruct.new(
      id: id,
      payload: payload,
      label_ids: label_ids,
      internal_date: internal_ms || (date.to_i * 1000)
    )
  end

  def list_page(ids, next_page_token: nil)
    OpenStruct.new(
      messages: ids.map { |id| OpenStruct.new(id: id) },
      next_page_token: next_page_token
    )
  end

  def history_page(added_ids, next_page_token: nil, top_history_id: nil)
    entries = added_ids.map.with_index do |id, idx|
      OpenStruct.new(
        id: (top_history_id || (1000 + idx)).to_s,
        messages_added: [OpenStruct.new(message: OpenStruct.new(id: id))]
      )
    end
    OpenStruct.new(history: entries, next_page_token: next_page_token)
  end

  # #574: Kontakt mit E-Mail anlegen → Adresse ist in der Sync-Allowlist.
  def allow_sender!(email, name: "Kontakt-#{SecureRandom.hex(2)}")
    ki = FileProxy.create(actor: @sync_actor, title: name, item_type: :person,
                          content: "", topics: [], contacts: [], tags: [])
    ki.contact_points.create!(kind: "email", value: email)
    ki
  end

  # #574: full_sync fragt erst das Label (Page 1), dann die Allowlist-Chunks.
  def curated_pages(allowlist_pages, label_page: list_page([]))
    [ label_page ] + allowlist_pages
  end

  # ─── Tests ──────────────────────────────────────────────────────────────

  test "full_sync (kuratiert) ingestiert Allowlist-Treffer und setzt last_history_id" do
    cred   = build_cred
    allow_sender!("sender-m1@x.io")
    allow_sender!("sender-m2@x.io")
    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[m1 m2]) ])
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "Subj #{id}", from: "sender-#{id}@x.io")
    }

    result = GmailSync.full_sync(cred, client: client)

    assert_equal 2, result.created
    assert_equal 0, result.skipped
    assert_equal 2, Communication.count
    assert_equal "12345", cred.reload.last_history_id
  end

  # #760 (Hans, 2026-06-23): Toter Refresh-Token (invalid_grant — Testing-
  # Modus-Ablauf, #687) deaktiviert das Konto (kein weiteres 15-min-Hämmern)
  # und liefert eine klare Reconnect-Meldung statt der rohen Signet-Fehlermeldung.
  test "toter Refresh-Token deaktiviert das Konto und meldet Reconnect" do
    cred = build_cred(expires_at: 1.hour.ago)   # expired → Refresh wird versucht
    assert cred.active?
    sync = GmailSync.new(cred)
    fake = Object.new
    def fake.refresh!; raise Signet::AuthorizationError, "invalid_grant: Token expired or revoked"; end
    sync.define_singleton_method(:signet_client) { fake }
    err = assert_raises(GmailSync::SyncError) { sync.send(:refresh_token_if_needed!) }
    assert_match(/neu verbinden/, err.message)
    refute cred.reload.active?, "Konto muss nach invalid_grant deaktiviert sein"
  end

  # #690 (Hans): Allowlist-Query muss ein- UND ausgehende Mails holen.
  test "full_sync fragt Allowlist mit from: UND to: ab" do
    cred = build_cred
    allow_sender!("kontakt@x.io")
    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page([]) ])

    GmailSync.full_sync(cred, client: client)

    queries     = client.calls.select { |c| c.first == :list_user_messages }.map { |c| c[2].to_s }
    allowlist_q = queries.find { |q| q.include?("kontakt@x.io") }
    assert allowlist_q, "Allowlist-Query nicht gefunden: #{queries.inspect}"
    assert_includes allowlist_q, "from:(kontakt@x.io"
    assert_includes allowlist_q, "to:(kontakt@x.io"
  end

  test "full_sync paginates" do
    cred   = build_cred
    client = FakeGmailClient.new
    allow_sender!("x@y.io")
    client.messages_pages = curated_pages([ list_page(%w[m1], next_page_token: "p2"),
                                            list_page(%w[m2]) ])
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "S", from: "x@y.io")
    }

    GmailSync.full_sync(cred, client: client)

    assert_equal 2, Communication.count
    list_calls = client.calls.select { |c| c.first == :list_user_messages }
    assert_equal 3, list_calls.size   # Label-Query + 2 Allowlist-Pages
  end

  test "sync without last_history_id falls back to full_sync" do
    cred = build_cred(last_history_id: nil)
    allow_sender!("a@b.io")
    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[x1]) ])
    client.get_message_handler = ->(id) { fake_message(id: id, subject: "S", from: "a@b.io") }

    GmailSync.sync(cred, client: client)
    assert_equal 1, Communication.count
  end

  test "incremental sync with last_history_id uses history.list" do
    cred = build_cred(last_history_id: "900")
    allow_sender!("a@b.io")
    client = FakeGmailClient.new
    client.history_pages = [ history_page(%w[m1 m2], top_history_id: 950) ]
    client.get_message_handler = ->(id) { fake_message(id: id, subject: "S", from: "a@b.io") }

    GmailSync.sync(cred, client: client)

    assert_equal 2, Communication.count
    history_calls = client.calls.select { |c| c.first == :list_user_histories }
    assert_equal 1, history_calls.size
  end

  test "deduplicates messages by external_id on re-run" do
    cred = build_cred
    allow_sender!("a@b.io")
    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[dup1 dup1]) ])
    client.get_message_handler = ->(id) { fake_message(id: id, subject: "S", from: "a@b.io") }

    GmailSync.full_sync(cred, client: client)
    assert_equal 1, Communication.count

    # Second run: already exists → skipped
    client.messages_pages = curated_pages([ list_page(%w[dup1]) ])
    result = GmailSync.full_sync(cred, client: client)
    assert_equal 0, result.created
    assert_equal 1, result.skipped
    assert_equal 1, Communication.count
  end

  test "marks outbound when From matches account email" do
    cred = build_cred(email_address: "hans@example.com")
    allow_sender!("alice@example.com")
    allow_sender!("bob@example.com")
    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[out1 in1]) ])
    client.get_message_handler = ->(id) {
      if id == "out1"
        fake_message(id: id, subject: "I sent this", from: "hans@example.com", to: "alice@example.com")
      else
        fake_message(id: id, subject: "I got this", from: "bob@example.com", to: "hans@example.com")
      end
    }

    GmailSync.full_sync(cred, client: client)

    assert Communication.find_by(external_id: "out1").outbound?
    assert Communication.find_by(external_id: "in1").inbound?
  end

  test "links to existing Person-KIs by email" do
    cred = build_cred
    alice = FileProxy.create(
      actor:     @sync_actor, title: "Alice Doe", item_type: :person,
      content: "", topics: [], contacts: [], tags: []
    )
    alice.update!(first_name: "Alice", last_name: "Doe")
    alice.contact_points.create!(kind: "email", value: "alice@example.com")

    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[m1]) ])
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "Hi", from: "alice@example.com", to: "bob@example.com")
    }

    GmailSync.full_sync(cred, client: client)

    comm = Communication.first
    assert_includes comm.mentioned_kis, alice
    # Note: bob hatte vorher KEINEN Treffer und wurde ignoriert. Neu: er
    # wird als Person-KI auto-angelegt und als Recipient verlinkt.
    bob_uuid = ContactPoint.where(kind: "email").where("lower(value) = ?", "bob@example.com").pick(:knowledge_item_uuid)
    bob_ki   = bob_uuid && KnowledgeItem.find_by(uuid: bob_uuid)
    assert_not_nil bob_ki, "unbekannter Empfänger sollte automatisch als Person-KI angelegt werden"
    assert_includes comm.mentioned_kis, bob_ki
  end

  test "unknown senders are auto-created as Person-KIs (über den Label-Kanal)" do
    cred = build_cred
    refute ContactPoint.where(kind: "email").where("lower(value) = ?", "newcomer@example.com").exists?

    client = FakeGmailClient.new
    # #574: unbekannter Absender kommt NUR über das miolimOS-Label rein.
    client.labels = [ OpenStruct.new(id: "Label_7", name: "miolimOS") ]
    client.messages_pages = curated_pages([], label_page: list_page(%w[m1]))
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "Hi", from: "newcomer@example.com", to: "hans@example.com",
                   label_ids: %w[Label_7 INBOX])
    }

    GmailSync.full_sync(cred, client: client)

    auto_uuid = ContactPoint.where(kind: "email").where("lower(value) = ?", "newcomer@example.com").pick(:knowledge_item_uuid)
    auto      = auto_uuid && KnowledgeItem.find_by(uuid: auto_uuid)
    assert_not_nil auto, "unbekannter Absender sollte automatisch als Person-KI angelegt werden"
    comm = Communication.first
    assert_includes comm.mentioned_kis, auto
    assert_equal ["sender"], comm.communication_mentions.where(mentioned_uuid: auto.uuid).pluck(:role)
  end

  # #794: idempotenter Garant — verlinkter Teilnehmer trägt seine Adresse.
  test "ensure_email_contact! hängt fehlende Adresse an, erhält bestehende, idempotent" do
    cred = build_cred
    sync = GmailSync.new(cred, client: FakeGmailClient.new)
    ki = FileProxy.create(actor: @sync_actor, title: "Hartmut", item_type: :person,
                          content: "", topics: [], contacts: [], tags: [])
    FileProxy.update(actor: @sync_actor, knowledge_item: ki,
                     contact_points: [{ "kind" => "phone", "label" => "", "value" => "030-1" }])
    ki.reload
    refute ki.contact_points.where(kind: "email").exists?

    sync.send(:ensure_email_contact!, ki, "Hartmut@Steubers.de", @sync_actor)
    ki.reload
    assert ki.contact_points.where(kind: "email").where("lower(value) = ?", "hartmut@steubers.de").exists?,
           "fehlende E-Mail muss nachgetragen werden"
    assert ki.contact_points.where(kind: "phone").exists?, "bestehender Kontaktpunkt bleibt erhalten"

    sync.send(:ensure_email_contact!, ki, "hartmut@steubers.de", @sync_actor)
    ki.reload
    assert_equal 1, ki.contact_points.where(kind: "email").count, "keine Dublette bei erneutem Aufruf"
  end

  # #768 v2: explizite Selbst-Identität + Policy.
  test "own_addresses nutzt die explizite Selbst-KI (Das bin ich)" do
    cred = build_cred
    selfki = FileProxy.create(actor: @sync_actor, title: "Ich Selbst", item_type: :person,
                              content: "", topics: [], contacts: [], tags: [])
    FileProxy.update(actor: @sync_actor, knowledge_item: selfki,
                     contact_points: [{ "kind" => "email", "label" => "", "value" => "me@private.de" }])
    @sync_actor.update!(person_ki_uuid: selfki.uuid)

    own = GmailSync.new(cred, client: FakeGmailClient.new).send(:own_addresses)
    assert_includes own, "me@private.de", "Adresse der Selbst-KI zählt als intern (nicht per Postfach ableitbar)"
    assert_includes own, cred.email_address.downcase, "Postfach zählt als intern"
  end

  test "Policy B (Default) = alle verbundenen Konten intern; A = nur der Inhaber" do
    cred_a = build_cred(email_address: "alice@example.com")
    build_cred(email_address: "bob@example.com") # zweites verbundenes Konto

    b = GmailSync.new(cred_a, client: FakeGmailClient.new).send(:own_addresses)
    assert_includes b, "alice@example.com"
    assert_includes b, "bob@example.com", "Policy B: fremdes verbundenes Konto ist intern"

    Setting.set("sync_exclude_internal_team", "false")
    a = GmailSync.new(cred_a, client: FakeGmailClient.new).send(:own_addresses)
    assert_includes a, "alice@example.com"
    refute_includes a, "bob@example.com", "Policy A: fremdes Konto ist NICHT intern"
  end

  test "links cc recipients with cc role" do
    cred = build_cred
    alice = FileProxy.create(
      actor: @sync_actor, title: "Alice Doe", item_type: :person,
      content: "", topics: [], contacts: [], tags: []
    )
    alice.update!(first_name: "Alice", last_name: "Doe")
    alice.contact_points.create!(kind: "email", value: "alice@example.com")
    carol = FileProxy.create(
      actor: @sync_actor, title: "Carol Doe", item_type: :person,
      content: "", topics: [], contacts: [], tags: []
    )
    carol.update!(first_name: "Carol", last_name: "Doe")
    carol.contact_points.create!(kind: "email", value: "carol@example.com")

    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[m1]) ])
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "Hi", from: "alice@example.com",
                   to: "hans@example.com", cc: "carol@example.com")
    }

    GmailSync.full_sync(cred, client: client)

    comm = Communication.first
    roles = comm.communication_mentions.includes(mentioned: :contact_points).map { |cm|
      [cm.mentioned&.contact_points&.emails&.first&.value, cm.role]
    }
    assert_includes roles, ["alice@example.com", "sender"]
    assert_includes roles, ["carol@example.com", "cc"]
  end

  test "body is decoded from base64url" do
    cred = build_cred
    allow_sender!("a@b.io")
    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[m1]) ])
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "S", from: "a@b.io", body_text: "hallo welt 🌍")
    }

    GmailSync.full_sync(cred, client: client)
    body = Communication.first.body.dup.force_encoding("UTF-8")
    assert_equal "hallo welt 🌍", body
  end

  test "sender with mixed case email still matches existing Person-KI" do
    cred = build_cred
    alice = FileProxy.create(
      actor: @sync_actor, title: "Alice Doe", item_type: :person,
      content: "", topics: [], contacts: [], tags: []
    )
    alice.update!(first_name: "Alice", last_name: "Doe")
    alice.contact_points.create!(kind: "email", value: "Alice@Example.COM")

    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[m1]) ])
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "S", from: "alice@EXAMPLE.com", to: "hans@example.com")
    }

    GmailSync.full_sync(cred, client: client)
    # alice (1× sender) + hans-recipient (auto-angelegt) = 2 mentions
    comm = Communication.first
    assert_includes comm.mentioned_kis.map(&:uuid), alice.uuid
    assert_equal ["sender"], comm.communication_mentions.where(mentioned_uuid: alice.uuid).pluck(:role)
  end

  test "malformed message is logged and counted as error, others continue" do
    cred = build_cred
    allow_sender!("a@b.io")
    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[good bad ugly]) ])
    client.get_message_handler = ->(id) {
      raise "boom" if id == "bad"
      fake_message(id: id, subject: "S", from: "a@b.io")
    }

    result = GmailSync.full_sync(cred, client: client)

    assert_equal 2, result.created
    assert_equal 1, result.errors
    assert_equal 2, Communication.count
  end
  # ── #574: Kuratierung ──────────────────────────────────────────────────────
  test "Gate: Mail ohne Label und ohne bekannten Beteiligten wird übersprungen" do
    cred = build_cred(last_history_id: "900")
    client = FakeGmailClient.new
    client.history_pages = [ history_page(%w[spam1], top_history_id: 950) ]
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "Newsletter", from: "noreply@werbung.example")
    }

    result = GmailSync.sync(cred, client: client)
    assert_equal 0, result.created
    assert_equal 1, result.skipped
    assert_equal 0, Communication.count
  end

  # #768 (Hans): Adressen des Kontoinhabers selbst — auch eine Zweit-/Alias-
  # Adresse, die als Kontaktpunkt seiner eigenen Person-KI in der Allowlist
  # steht — dürfen NICHT als bekannter Beteiligter zählen. Sonst wird jede
  # Mail importiert, bei der Hans nur Empfänger ist.
  test "Gate #768: Mail nur an eigene Alias-Adresse des Inhabers wird abgelehnt" do
    cred = build_cred(email_address: "owner@example.com")
    # Self-KI: eine Adresse == verbundenes Postfach → als Inhaber erkannt;
    # die Alias-Adresse zählt dann ebenfalls als „eigen".
    self_ki = allow_sender!("owner@example.com", name: "Hans (ich)")
    self_ki.contact_points.create!(kind: "email", value: "owner-alias@example.com")
    sync = GmailSync.new(cred, client: FakeGmailClient.new)

    msg    = fake_message(id: "x", subject: "Newsletter",
                          from: "noreply@werbung.example", to: "owner-alias@example.com")
    parsed = GmailSync::MessageParser.parse(msg, account_email: cred.email_address)
    refute sync.send(:accepted?, msg, parsed),
      "Mail nur an eine eigene Adresse des Inhabers darf nicht akzeptiert werden"
    # Eigene Adressen sind aus der Allowlist ausgenommen:
    refute_includes sync.send(:allowlisted_emails), "owner-alias@example.com"
    refute_includes sync.send(:allowlisted_emails), "owner@example.com"
  end

  test "Gate #768: Mail eines bekannten Kontakts an den Inhaber wird akzeptiert" do
    cred = build_cred(email_address: "owner@example.com")
    self_ki = allow_sender!("owner@example.com", name: "Hans (ich)")
    self_ki.contact_points.create!(kind: "email", value: "owner-alias@example.com")
    allow_sender!("kunde@firma.example", name: "Kunde")
    sync = GmailSync.new(cred, client: FakeGmailClient.new)

    msg    = fake_message(id: "y", subject: "Anfrage",
                          from: "kunde@firma.example", to: "owner-alias@example.com")
    parsed = GmailSync::MessageParser.parse(msg, account_email: cred.email_address)
    assert sync.send(:accepted?, msg, parsed),
      "Mail eines bekannten Kontakts an den Inhaber muss akzeptiert werden"
  end

  test "Allowlist-Query trägt das sync_since-Startdatum" do
    cred = build_cred(sync_since: Time.utc(2026, 6, 10))
    allow_sender!("kunde@firma.example")
    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page([]) ])
    GmailSync.full_sync(cred, client: client)

    queries = client.calls.select { |c| c.first == :list_user_messages }.map { |c| c[2] }
    assert_equal "label:miolimOS", queries.first
    assert_includes queries.last, "from:(kunde@firma.example"
    assert_includes queries.last, "after:2026/06/10"
  end

  test "K2: Mail eines Projekt-Kunden hängt automatisch am Projekt" do
    cred  = build_cred
    alice = allow_sender!("alice@kunde.example", name: "Alice Kundin")
    projekt = Topic.create!(name: "Kundenprojekt", slug: "kp-#{SecureRandom.hex(3)}",
                            creator: @sync_actor, customer_uuid: alice.uuid)

    client = FakeGmailClient.new
    client.messages_pages = curated_pages([ list_page(%w[m1]) ])
    client.get_message_handler = ->(id) {
      fake_message(id: id, subject: "Projektfrage", from: "alice@kunde.example")
    }

    GmailSync.full_sync(cred, client: client)
    comm = Communication.first
    assert_equal [ projekt.id ], comm.topics.pluck(:id),
      "Mail der Projekt-Kundin muss automatisch am Projekt hängen"
  end

  # ─── #1055: prune — der destruktive Zweig (Remote-Löschung → lokales
  # destroy!) war ungetestet. Wichtig: NUR die gemeldete Mail fliegt,
  # Task-Backlinks werden genullt (dependent: :nullify), unbekannte IDs
  # sind No-Ops, Fehler beim Löschen zählen als error statt zu raisen. ───

  def deleted_history_page(deleted_ids, top_history_id: 1500)
    entries = deleted_ids.map.with_index do |id, idx|
      OpenStruct.new(
        id: (top_history_id + idx).to_s,
        messages_deleted: [OpenStruct.new(message: OpenStruct.new(id: id))]
      )
    end
    OpenStruct.new(history: entries, next_page_token: nil)
  end

  test "prune: remote gelöschte Mail wird lokal entfernt, Task-Backlink genullt, andere bleiben" do
    cred  = build_cred(last_history_id: "900")
    gone  = Email.create!(external_id: "gone-1", subject: "Alte Mail")
    stays = Email.create!(external_id: "stays-1", subject: "Bleibt")
    task  = Task.create!(title: "Folge-Aufgabe", creator: @sync_actor, communication: gone)

    client = FakeGmailClient.new
    client.history_pages = [ deleted_history_page(%w[gone-1]) ]
    result = GmailSync.sync(cred, client: client)

    assert_equal 1, result.deleted
    assert_nil Communication.find_by(external_id: "gone-1")
    assert Communication.exists?(stays.id), "nicht gemeldete Mail darf nicht gelöscht werden"
    task.reload
    assert_nil task.communication_id
    assert Task.exists?(task.id), "Task mit Backlink muss überleben"
  end

  test "prune: unbekannte Message-ID ist ein No-Op, TRASH-Label löscht ebenfalls" do
    cred = build_cred(last_history_id: "900")
    trashed = Email.create!(external_id: "trash-1", subject: "In den Papierkorb")

    client = FakeGmailClient.new
    trash_entry = OpenStruct.new(
      id: "1600",
      labels_added: [OpenStruct.new(message: OpenStruct.new(id: "trash-1"),
                                    label_ids: ["TRASH"])]
    )
    unknown_entry = OpenStruct.new(
      id: "1601",
      messages_deleted: [OpenStruct.new(message: OpenStruct.new(id: "nie-gesehen"))]
    )
    client.history_pages = [ OpenStruct.new(history: [trash_entry, unknown_entry], next_page_token: nil) ]
    result = GmailSync.sync(cred, client: client)

    assert_equal 1, result.deleted, "TRASH-Label muss prunen, unbekannte ID nicht zählen"
    assert_equal 0, result.errors
    assert_nil Communication.find_by(external_id: "trash-1")
  end
end
