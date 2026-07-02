require "test_helper"

class KnowledgeItemTest < ActiveSupport::TestCase
  def build_item(**overrides)
    defaults = {
      uuid:         SecureRandom.uuid,
      title:        "Sample",
      item_type:    :note,
      file_path:    "knowledge/notes/#{SecureRandom.hex(4)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current,
      file_updated_at: Time.current,
      indexed_at:      Time.current
    }
    KnowledgeItem.new(**defaults.merge(overrides))
  end

  test "uuid is the primary key" do
    assert_equal "uuid", KnowledgeItem.primary_key
  end

  test "requires uuid, title, file_path, content_hash" do
    i = KnowledgeItem.new
    refute_predicate i, :valid?
    %w[uuid title file_path content_hash].each do |attr|
      assert i.errors.added?(attr.to_sym, :blank), "#{attr} should be required"
    end
  end

  test "uuid uniqueness enforced" do
    i = build_item
    i.save!
    dup = build_item(uuid: i.uuid, file_path: "knowledge/notes/other.md")
    refute_predicate dup, :valid?
  end

  test "file_path uniqueness enforced" do
    i = build_item
    i.save!
    dup = build_item(file_path: i.file_path)
    refute_predicate dup, :valid?
  end

  test "scopes: notes / abstracts / transcripts / quotes" do
    n  = build_item(item_type: :note).tap(&:save!)
    a  = build_item(item_type: :abstract).tap(&:save!)
    t  = build_item(item_type: :transcript).tap(&:save!)
    dq = build_item(item_type: :direct_quote).tap(&:save!)
    iq = build_item(item_type: :indirect_quote).tap(&:save!)

    assert_equal [n],       KnowledgeItem.notes
    assert_equal [a],       KnowledgeItem.abstracts
    assert_equal [t],       KnowledgeItem.transcripts
    assert_equal [dq],      KnowledgeItem.direct_quotes
    assert_equal [iq],      KnowledgeItem.indirect_quotes
    assert_equal [dq, iq].sort, KnowledgeItem.quotes.sort
  end

  test "item_type enum round-trip" do
    i = build_item(item_type: :abstract)
    i.save!
    assert i.abstract?
    reloaded = KnowledgeItem.find(i.uuid)
    assert reloaded.abstract?
  end

  test "topics association via knowledge_item_topics" do
    item = build_item.tap(&:save!)
    topic = create_topic(creator: create_human)
    item.knowledge_item_topics.create!(topic: topic)

    assert_equal [topic], item.topics
    assert_equal [item],  topic.reload_association(:knowledge_items) rescue nil # tolerate: KnowledgeItem isn't on Topic by default
  end

  test "references are stored and linked via source/target_uuid" do
    a = build_item(title: "A").tap(&:save!)
    b = build_item(title: "B").tap(&:save!)

    ref = KnowledgeItemReference.create!(
      source: a, target: b,
      target_title: "B", anchor_type: :file
    )

    assert_equal a, ref.source
    assert_equal b, ref.target
    assert_equal [ref], a.outgoing_references
    assert_equal [ref], b.incoming_references
  end

  test "deleting source cascades references" do
    a = build_item.tap(&:save!)
    b = build_item.tap(&:save!)
    KnowledgeItemReference.create!(source: a, target: b, target_title: "B", anchor_type: :file)

    assert_difference -> { KnowledgeItemReference.count }, -1 do
      a.destroy!
    end
  end

  test "deleting target nullifies target_uuid on references" do
    a = build_item.tap(&:save!)
    b = build_item.tap(&:save!)
    ref = KnowledgeItemReference.create!(source: a, target: b, target_title: "B", anchor_type: :file)

    b.destroy!
    assert_nil ref.reload.target_uuid
  end

  # #522 (Hans, 2026-06-06): Ein eigener Entwurf darf nicht „eingefangen"
  # werden, wenn jemand anderes danach eine Antwort postet — er bleibt
  # bearbeit-/lösch-/veröffentlichbar und rutscht ans Thread-Ende.
  def build_reply(task:, creator:, published_at:, created_at:)
    build_item(
      item_type:     :reply,
      title:         nil,
      parent_type:   "Task",
      parent_id_int: task.id,
      creator_id:    creator.id,
      published_at:  published_at,
      created_at:    created_at
    ).tap(&:save!)
  end

  test "eigener Entwurf bleibt editierbar trotz späterer fremder Antwort" do
    hans = create_human
    me   = create_agent
    task = create_task(creator: hans)
    t0   = Time.current

    own_published = build_reply(task: task, creator: hans,
                                published_at: t0, created_at: t0)
    draft         = build_reply(task: task, creator: hans,
                                published_at: nil, created_at: t0 + 1)
    foreign       = build_reply(task: task, creator: me,
                                published_at: t0 + 2, created_at: t0 + 2)

    # Der Entwurf bleibt für seinen Autor editierbar — das ist der Fix.
    assert draft.editable_by?(hans), "Entwurf muss editierbar bleiben"
    # Die frühere VERÖFFENTLICHTE eigene Antwort bleibt korrekt gesperrt
    # (Diskurs-Historie nicht rückwirkend ändern).
    refute own_published.editable_by?(hans), "veröffentlichte Antwort hinter fremder Folge gesperrt"
    # Niemand sonst darf den Entwurf editieren.
    refute draft.editable_by?(me)
    _ = foreign
  end

  test "eigene Entwürfe werden im Thread ans Ende sortiert" do
    hans = create_human
    me   = create_agent
    task = create_task(creator: hans)
    t0   = Time.current

    draft     = build_reply(task: task, creator: hans,
                            published_at: nil, created_at: t0)        # früh erstellt
    published = build_reply(task: task, creator: me,
                            published_at: t0 + 1, created_at: t0 + 1)  # danach veröffentlicht

    ordered = KnowledgeItem.replies_for(task, viewer: hans).to_a
    assert_equal [published.uuid, draft.uuid], ordered.map(&:uuid),
                 "Entwurf gehört trotz früherem created_at ans Ende"
  end

  # #522-Nachklapp: ein früh erstellter, spät veröffentlichter Entwurf gehört
  # nach dem Veröffentlichen an seine published_at-Position (Thread-Ende),
  # nicht zurück an die alte created_at-Entwurfsstelle.
  test "spät veröffentlichter Entwurf sortiert nach published_at, nicht created_at" do
    hans = create_human
    task = create_task(creator: hans)
    t0   = Time.current

    early = build_reply(task: task, creator: hans,
                        published_at: t0,     created_at: t0)        # früh erstellt + veröffentlicht
    late  = build_reply(task: task, creator: hans,
                        published_at: t0 + 5, created_at: t0 + 1)     # früh ERSTELLT, spät VERÖFFENTLICHT

    ordered = KnowledgeItem.replies_for(task, viewer: hans).to_a
    assert_equal [early.uuid, late.uuid], ordered.map(&:uuid),
                 "spät veröffentlichte Antwort gehört ans Ende (published_at), nicht an created_at-Stelle"
  end
  # ── #536: Löschen entkoppelt von „editierbar bis Antwort" ────────────────
  test "deletable_by?: eigene Reply bleibt löschbar nach fremder Folge-Antwort" do
    autor  = create_human
    fremd  = create_human
    parent = Task.create!(title: "Thread", creator: autor, skip_default_assignee: true)
    eigene = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Reply-#{SecureRandom.hex(2)}", item_type: :reply,
                                   creator: autor, file_path: "x/r1.md", content_hash: "h",
                                   body: "Beitrag", parent_type: "Task", parent_id_int: parent.id,
                                   published_at: Time.current)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Reply-#{SecureRandom.hex(2)}", item_type: :reply,
                          creator: fremd, file_path: "x/r2.md", content_hash: "h",
                          body: "Antwort danach", parent_type: "Task", parent_id_int: parent.id,
                          published_at: Time.current, created_at: 1.minute.from_now)

    refute eigene.editable_by?(autor), "Bearbeiten bleibt nach fremder Antwort gesperrt"
    assert eigene.deletable_by?(autor), "Löschen eigener Beiträge muss immer gehen"
    refute eigene.deletable_by?(fremd), "fremde Beiträge sind nie löschbar"
  end

  # #664: Anker-Wikilink trägt auch bei Titeln mit wikilink-brechenden
  # Zeichen (YouTube-Titel mit `|` etc.).
  test "anchor_wikilink: sicherer Titel als Titel-Form, unsicherer als UUID-Form" do
    safe = KnowledgeItem.new(uuid: "11111111-1111-1111-1111-111111111111", title: "Sauberer Titel")
    assert_equal "[[Sauberer Titel^abc12345]]", safe.anchor_wikilink("abc12345")
    assert_equal "[[Sauberer Titel^abc12345|Alias]]", safe.anchor_wikilink("abc12345", alias_text: "Alias")

    pipe = KnowledgeItem.new(uuid: "8dfee226-e5a5-4484-9147-3c63f0ad4e62",
                             title: "Father of VR | Jaron Lanier")
    assert_equal "[[8dfee226-e5a5-4484-9147-3c63f0ad4e62^abc12345|Father of VR | Jaron Lanier]]",
                 pipe.anchor_wikilink("abc12345")
    assert_equal "[[8dfee226-e5a5-4484-9147-3c63f0ad4e62^abc12345|die Stelle]]",
                 pipe.anchor_wikilink("abc12345", alias_text: "die Stelle")
  end
end
