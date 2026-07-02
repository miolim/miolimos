require "test_helper"

class KnowledgeCreatorBackfillTest < ActiveSupport::TestCase
  setup do
    @hans = create_human(name: "Hans", email: "hans@miolim.de")
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  test "resolves creator from first git-commit author email" do
    with_isolated_miolimos_base do |base|
      item = FileProxy.create(actor: @hans, title: "Backfill-Test",
                              item_type: :note, content: "x")
      # Vor-Migrations-Zustand simulieren: creator_id wieder leeren.
      item.update_column(:creator_id, nil)

      stats = KnowledgeCreatorBackfill.run
      assert_equal 1, stats.scanned
      assert_equal 1, stats.resolved
      assert_equal 0, stats.unresolved
      assert_equal @hans.id, item.reload.creator_id
    end
  end

  test "unresolved items are left with creator_id NULL" do
    with_isolated_miolimos_base do |base|
      item = FileProxy.create(actor: @hans, title: "Stranded",
                              item_type: :note, content: "x")
      item.update_column(:creator_id, nil)
      # Hans entfernen — der Author im Git ist dann nicht mehr auflösbar
      @hans.destroy

      stats = KnowledgeCreatorBackfill.run
      assert_equal 1, stats.scanned
      assert_equal 0, stats.resolved
      assert_equal 1, stats.unresolved
      assert_nil item.reload.creator_id
    end
  end

  test "items with creator_id already set are skipped (idempotent)" do
    with_isolated_miolimos_base do
      FileProxy.create(actor: @hans, title: "Already mapped",
                       item_type: :note, content: "x")
      # KI hat bereits creator_id — soll nicht angefasst werden
      stats = KnowledgeCreatorBackfill.run
      assert_equal 0, stats.scanned, "Bereits zugeordnete KIs werden ignoriert"
    end
  end

  test "fallback to inbox_item.creator when no git author is available" do
    with_isolated_miolimos_base do |base|
      classifier = create_agent(name: "Email-Classifier")
      grant(classifier, "KnowledgeItem", %w[read create])
      inbox = InboxItem.create!(
        source_kind: "markdown", raw_content: "x", title: "I", status: "pending",
        creator: @hans
      )
      item = FileProxy.create(actor: classifier, title: "From-Inbox",
                              item_type: :note, content: "x")
      item.update_columns(creator_id: nil, inbox_item_id: inbox.id)
      # Der Classifier ist Author im Git, also wird er regulär resolved.
      # Wir wollen den Inbox-Fallback testen — Classifier weg, dann steht
      # nur noch das Inbox-Item als Quelle.
      classifier.destroy

      stats = KnowledgeCreatorBackfill.run
      assert_equal 1, stats.scanned
      assert_equal 1, stats.resolved
      assert_equal 1, stats.resolved_via_inbox
      assert_equal @hans.id, item.reload.creator_id
    end
  end

  test "name-fallback when email does not match an Actor" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "Name-fallback",
                              item_type: :note, content: "x")
      item.update_column(:creator_id, nil)
      # Email umstellen, sodass die im Commit gespeicherte Email keinen
      # Actor mehr findet — Name "Hans" muss aber noch matchen.
      @hans.update!(email: "neue-mail@miolim.de")

      stats = KnowledgeCreatorBackfill.run
      assert_equal 1, stats.resolved
      assert_equal @hans.id, item.reload.creator_id
    end
  end
end
