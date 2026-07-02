require "test_helper"

class CommunicationTest < ActiveSupport::TestCase
  def build_cred(email:)
    OauthCredential.create!(
      actor:         create_human,
      provider:      "google",
      email_address: email,
      access_token:  "a",
      refresh_token: "r",
      expires_at:    1.hour.from_now,
      scopes:        []
    )
  end

  def build_email(**overrides)
    defaults = {
      subject:     "Hi",
      body:        "Body",
      sent_at:     Time.current,
      direction:   :inbound,
      external_id: "gmail-#{SecureRandom.hex(6)}"
    }
    Email.new(**defaults.merge(overrides))
  end

  # #695 (Hans): Tags <-> zentrale Tagging-Registry synchron.
  test "Tags synchronisieren in die Tagging-Registry und werden normalisiert" do
    e = build_email
    e.save!
    e.update!(tags: ["Rechnung", "WICHTIG"])
    names = -> { Tagging.where(taggable_type: "Communication", taggable_id_int: e.id).joins(:tag).pluck("tags.name").sort }
    assert_equal %w[rechnung wichtig], names.call   # downcase
    e.update!(tags: ["rechnung"])                    # eines entfernt
    assert_equal %w[rechnung], names.call
    e.destroy!
    assert_equal 0, Tagging.where(taggable_type: "Communication", taggable_id_int: e.id).count
  end

  # #697 (Hans): rohe Teilnehmer-Adresse live über E-Mail-Kontaktpunkt auflösen.
  test "participants_for löst Adressen live über E-Mail-Kontaktpunkte auf" do
    ki = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Kontakt X", item_type: :person,
                               file_path: "kb/#{SecureRandom.hex(4)}.md", content_hash: SecureRandom.hex(8))
    ContactPoint.create!(knowledge_item_uuid: ki.uuid, kind: "email", value: "x@example.com")
    e = build_email(participants: { "sender" => ["X@Example.com"], "recipient" => ["unknown@example.com"] })
    e.save!
    sender = e.participants_for("sender")     # ohne Mention — nur über Kontaktpunkt
    assert_equal ki.uuid, sender.first[:ki]&.uuid
    assert_equal "unknown@example.com", e.participants_for("recipient").first[:email]  # nicht auflösbar → roh
  end

  test "requires external_id and type" do
    c = Communication.new(type: "Email")
    refute_predicate c, :valid?
    assert c.errors.added?(:external_id, :blank)
  end

  test "external_id is unique" do
    build_email(external_id: "dup-xid").save!
    dup = build_email(external_id: "dup-xid")
    refute_predicate dup, :valid?
  end

  test "direction enum and scopes" do
    inb = build_email(direction: :inbound).tap(&:save!)
    out = build_email(direction: :outbound).tap(&:save!)

    assert_includes Communication.inbound,  inb
    refute_includes Communication.inbound,  out
    assert_includes Communication.outbound, out
  end

  test "STI: Email rows are returned as Email instances" do
    build_email.save!
    instance = Communication.first
    assert_kind_of Email, instance
    assert_equal "Email", instance.type
  end

  test "for_account scope joins through oauth_credential" do
    cred_a = build_cred(email: "a-#{SecureRandom.hex(4)}@x.io")
    cred_b = build_cred(email: "b-#{SecureRandom.hex(4)}@x.io")
    ea = build_email(oauth_credential: cred_a).tap(&:save!)
    eb = build_email(oauth_credential: cred_b).tap(&:save!)

    assert_includes Communication.for_account(cred_a.email_address), ea
    refute_includes Communication.for_account(cred_a.email_address), eb
  end

  test "communication_mentions roles" do
    comm = build_email.tap(&:save!)
    contact_ki = KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: "J D",
      item_type: :person,
      first_name: "J", last_name: "D",
      file_path: "knowledge/people/jd-#{SecureRandom.hex(3)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current, file_updated_at: Time.current,
      indexed_at: Time.current
    )

    CommunicationMention.create!(communication: comm, mentioned_uuid: contact_ki.uuid, role: "sender")
    CommunicationMention.create!(communication: comm, mentioned_uuid: contact_ki.uuid, role: "recipient")

    assert_equal 2, comm.communication_mentions.count

    dup = CommunicationMention.new(communication: comm, mentioned_uuid: contact_ki.uuid, role: "sender")
    refute_predicate dup, :valid?
  end

  test "unread? true for inbound without read_at, false for outbound or read" do
    inb_new = build_email(direction: :inbound).tap(&:save!)
    inb_read = build_email(direction: :inbound, read_at: Time.current).tap(&:save!)
    out = build_email(direction: :outbound).tap(&:save!)

    assert_predicate inb_new, :unread?
    refute_predicate inb_read, :unread?
    refute_predicate out, :unread?
  end

  test "unread scope filters to inbound with read_at nil" do
    inb_new = build_email(direction: :inbound).tap(&:save!)
    build_email(direction: :inbound, read_at: Time.current).tap(&:save!)
    build_email(direction: :outbound).tap(&:save!)

    assert_includes Communication.unread, inb_new
    assert_equal 1, Communication.unread.count
  end

  test "mark_read! sets read_at only for unread inbound" do
    inb = build_email(direction: :inbound).tap(&:save!)
    inb.mark_read!
    assert_not_nil inb.reload.read_at

    t_before = inb.read_at
    travel_to 1.second.from_now do
      inb.mark_read!
      assert_equal t_before, inb.reload.read_at
    end
  end

  test "task can belong to a communication" do
    comm = build_email.tap(&:save!)
    hans = create_human
    t = Task.create!(title: "from email", creator: hans, communication: comm)
    assert_equal comm, t.communication
    assert_includes comm.tasks, t
  end
end
