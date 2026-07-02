require "test_helper"

# #529 (Hans, 2026-06-06): TaskComment-Modell-Logik war ungetestet, obwohl
# der Lebenszyklus (Entwurf → veröffentlicht, Sichtbarkeit, „editierbar bis
# Antwort") subtil ist — #522 hat das bei der analogen Reply-KI-Logik gezeigt.
class TaskCommentTest < ActiveSupport::TestCase
  setup do
    @hans  = create_human(name: "Hans")
    @other = create_human(name: "Andere")
    @task  = create_task(creator: @hans)
  end

  def comment(actor: @hans, body: "hi", published_at: Time.current, created_at: nil)
    attrs = { task: @task, actor: actor, body: body, published_at: published_at }
    attrs[:created_at] = created_at if created_at
    TaskComment.create!(**attrs)
  end

  test "body ist Pflicht" do
    c = TaskComment.new(task: @task, actor: @hans)
    refute_predicate c, :valid?
    assert c.errors.added?(:body, :blank)
  end

  test "draft? hängt an published_at" do
    assert_predicate comment(published_at: nil), :draft?
    refute_predicate comment(published_at: Time.current), :draft?
  end

  test "publish! veröffentlicht nur Entwürfe und ist idempotent" do
    draft = comment(published_at: nil)
    draft.publish!
    refute_predicate draft, :draft?
    stamp = draft.published_at
    draft.publish!   # erneut — darf den Zeitstempel nicht verschieben
    assert_equal stamp, draft.reload.published_at
  end

  test "published-Scope und drafts-Scope trennen sauber" do
    pub = comment(published_at: Time.current)
    dr  = comment(published_at: nil)
    assert_includes @task.comments.published, pub
    refute_includes @task.comments.published, dr
    assert_includes @task.comments.drafts, dr
    refute_includes @task.comments.drafts, pub
  end

  test "visible_to?: Entwurf nur für den Autor, Veröffentlichtes für alle" do
    draft = comment(actor: @hans, published_at: nil)
    assert draft.visible_to?(@hans)
    refute draft.visible_to?(@other)

    pub = comment(actor: @hans, published_at: Time.current)
    assert pub.visible_to?(@hans)
    assert pub.visible_to?(@other)
  end

  test "editable_by?: nur der Autor" do
    c = comment(actor: @hans)
    refute c.editable_by?(@other)
    refute c.editable_by?(nil)
  end

  test "editable_by?: eigener Entwurf bleibt editierbar trotz späterer Antwort" do
    t0    = Time.current
    draft = comment(actor: @hans, published_at: nil,    created_at: t0)
    comment(actor: @other, published_at: t0 + 1,        created_at: t0 + 1) # fremde Folge-Antwort
    assert draft.editable_by?(@hans), "Entwurf muss editierbar bleiben"
  end

  test "editable_by?: nur die JÜNGSTE veröffentlichte eigene Antwort ist editierbar" do
    t0     = Time.current
    older  = comment(actor: @hans, published_at: t0,     created_at: t0)
    newer  = comment(actor: @hans, published_at: t0 + 2, created_at: t0 + 2)
    assert newer.editable_by?(@hans),  "jüngste veröffentlichte Antwort editierbar"
    refute older.editable_by?(@hans),  "ältere veröffentlichte Antwort gesperrt (Historie)"
  end

  test "read_by?: eigene Kommentare gelten als gelesen, fremde erst nach CommentRead" do
    c = comment(actor: @hans, published_at: Time.current)
    assert c.read_by?(@hans), "eigener Kommentar ist per Definition gelesen"
    refute c.read_by?(@other)
    CommentRead.create!(task_comment: c, actor: @other, read_at: Time.current)
    assert c.read_by?(@other)
  end

  test "unread_for-Scope: ohne eigene und ohne bereits gelesene" do
    own    = comment(actor: @hans,  published_at: Time.current)
    unread = comment(actor: @other, published_at: Time.current)
    read   = comment(actor: @other, published_at: Time.current)
    CommentRead.create!(task_comment: read, actor: @hans, read_at: Time.current)

    result = @task.comments.unread_for(@hans)
    assert_includes    result, unread
    refute_includes    result, own
    refute_includes    result, read
  end
end
