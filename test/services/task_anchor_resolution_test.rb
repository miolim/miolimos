require "test_helper"

# #480 Increment 3 (Hans, 2026-06-03): Absatz-Anker an einer Task-Description.
# Deckt die Kette ab, die der Picker im Topic-Blade nutzt:
#   ensure! (task-aware) -> after_save TaskAnchors::Sync -> Wikilink-Resolver.
class TaskAnchorResolutionTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
  end

  test "ensure! stabilisiert einen Anker in der Task-Description" do
    task = create_task(creator: @hans,
      description: "Erster Absatz.\n\nZweiter Absatz.\n\nDritter Absatz.")
    anchor = KnowledgeBlockAnchor.new(task, actor: @hans).ensure!(2)

    assert_match(/\A[a-f0-9]{8}\z/, anchor)
    task.reload
    assert_match(/Zweiter Absatz\.\s+\^#{anchor}\b/, task.description)
    assert_no_match(/Erster Absatz\.\s+\^/, task.description)
  end

  test "after_save indiziert Description-Anker in task_anchors" do
    task = create_task(creator: @hans, description: "Nur ein Absatz.")
    anchor = KnowledgeBlockAnchor.new(task, actor: @hans).ensure!(1)

    assert TaskAnchor.exists?(task_id: task.id, anchor: anchor)
  end

  test "[[^anker]] loest auf den Task-Absatz auf" do
    task = create_task(creator: @hans, description: "Ein Absatz hier.")
    anchor = KnowledgeBlockAnchor.new(task, actor: @hans).ensure!(1)

    html = KnowledgeMarkdown.render("[[^#{anchor}|Hierhin]]")
    assert_includes html, "/tasks?stack=task:#{task.id}##{anchor}"
    assert_includes html, ">Hierhin</a>"
  end

  test "obsolete Anker werden beim Re-Sync entfernt" do
    task = create_task(creator: @hans, description: "Absatz A.\n\nAbsatz B.")
    a = KnowledgeBlockAnchor.new(task, actor: @hans).ensure!(1)
    assert TaskAnchor.exists?(anchor: a)

    # Anker aus der Description loeschen -> Sync raeumt die Tabelle auf.
    task.update!(description: "Absatz A ohne Anker.")
    assert_not TaskAnchor.exists?(anchor: a)
  end
end
