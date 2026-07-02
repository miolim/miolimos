require "test_helper"

# #378 (Hans, 2026-05-26): Tests fuer WikilinkTargets — extrahiert
# `[[Title]]`-Wikilinks aus dem KI-Body, dedupliziert, resolviert zu
# KnowledgeItems. Genutzt vom Reference-Blade (#343) + Topic-Refs (#352).
class WikilinkTargetsTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Topic", %w[read create update delete])
    # #602 S1: WikilinkTargets filtert Ziele über Current.actor (im
    # Web-Request gesetzt) — Service-Test setzt ihn explizit.
    Current.actor = @hans
  end

  def create_note(title, body)
    FileProxy.create(actor: @hans, title: title, item_type: :note, content: body)
  end

  test "for returns empty array when item is nil" do
    assert_equal [], WikilinkTargets.for(nil)
  end

  test "for returns empty array when body is blank" do
    with_isolated_miolimos_base do
      item = create_note("X", "")
      assert_equal [], WikilinkTargets.for(item)
    end
  end

  test "for extracts wikilinks in source order without duplicates" do
    with_isolated_miolimos_base do
      t1 = create_note("Alpha", "x")
      t2 = create_note("Beta",  "y")
      src = create_note("Source", "Verweis auf [[Beta]] und [[Alpha]], dann nochmal [[Alpha]].")

      targets = WikilinkTargets.for(src)

      assert_equal %w[Beta Alpha], targets.map(&:title)
    end
  end

  test "for skips wikilinks whose target does not resolve" do
    with_isolated_miolimos_base do
      t1 = create_note("Alpha", "x")
      src = create_note("Source", "[[Alpha]] und [[Phantom]] und [[Alpha]].")

      titles = WikilinkTargets.for(src).map(&:title)
      assert_equal %w[Alpha], titles
    end
  end

  test "for_topic aggregates over all work-tree KIs of the topic" do
    with_isolated_miolimos_base do
      target_a = create_note("TargetA", "a")
      target_b = create_note("TargetB", "b")
      ki1 = create_note("Node1", "siehe [[TargetA]]")
      ki2 = create_note("Node2", "vergleich mit [[TargetB]] und [[TargetA]]")

      topic = Topic.create!(name: "T", slug: "t", creator: @hans)
      KnowledgeItemTopic.create!(knowledge_item_uuid: ki1.uuid, topic: topic)
      KnowledgeItemTopic.create!(knowledge_item_uuid: ki2.uuid, topic: topic)
      WorkNodeOps.create(topic: topic, knowledge_item: ki1, role: "heading")
      WorkNodeOps.create(topic: topic, knowledge_item: ki2, role: "content")

      titles = WikilinkTargets.for_topic(topic).map(&:title)
      assert_equal %w[TargetA TargetB], titles
    end
  end

  test "for_topic returns empty array for nil topic" do
    assert_equal [], WikilinkTargets.for_topic(nil)
  end
end
