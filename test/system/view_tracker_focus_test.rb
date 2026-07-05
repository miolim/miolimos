require "application_system_test_case"

# #816: Verlaufs-Tracking zählt nur die AKTIVE (fokussierte) Card eines
# Stacks — nicht alle offenen Cards, und bloßes Aufräumen erzeugt keine
# Einträge.
class ViewTrackerFocusTest < ApplicationSystemTestCase
  test "only the active stack card accumulates history views" do
    hans = create_human
    grant(hans, "KnowledgeItem", %w[read create update])
    grant(hans, "Task", %w[read])
    grant(hans, "Topic", %w[read])
    grant(hans, "Actor", %w[read update])  # actor_views-POST läuft über das Actor-Gate

    a = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Karte Aktiv", item_type: "note",
                              creator: hans, file_path: "x/a.md", content_hash: "h", body: "A")
    b = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Karte Passiv", item_type: "note",
                              creator: hans, file_path: "x/b.md", content_hash: "h", body: "B")
    login_as(hans)

    # Beide Cards im Stack; die ZULETZT geladene ist aktiv (connect → setActiveCard(last)).
    visit "/knowledge_items?stack=#{b.uuid},#{a.uuid}"
    assert page.has_css?("article.stack-card[data-uuid='#{a.uuid}'][data-active='true']", wait: 10)
    assert page.has_css?("article.stack-card[data-uuid='#{b.uuid}'][data-active='false']")

    sleep 3.6  # Threshold (3s) überschreiten — nur die aktive Card darf pingen

    views = ActorView.where(actor: hans).pluck(:viewable_id)
    assert_includes views, a.uuid, "aktive Card muss im Verlauf landen"
    assert_not_includes views, b.uuid, "passive Card darf NICHT im Verlauf landen (#816)"
  end
end
