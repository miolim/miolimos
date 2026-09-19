require "test_helper"

# #1675 (Fund 2 der Testabdeckungs-Durchsicht): Die Hauptseiten prüfen die
# Sichtbarkeit aus #602 — die Unter-Adressen einer Aufgabe oder eines
# Wissenseintrags taten es nicht. Rund ein Dutzend verschachtelte Controller
# holten ihr Elternobjekt ungefiltert (`Task.find(params[:task_id])`). Ein
# Mitglied konnte so die Antworten einer fremden, geheimen Aufgabe lesen, sie
# kommentieren — und sie per POST /tasks/<id>/topics in ein eigenes Thema
# hängen, wonach sie ihm ganz gehörte. Aufgaben-Nummern sind fortlaufend.
#
# Regel jetzt, an EINER Stelle (ApplicationController#find_visible!):
#   nicht sichtbar            → 404, wie auf den Hauptseiten
#   sichtbar, nur lesbar      → Lesen ja, jede Änderung 403
#   sichtbar und schreibbar   → wie bisher
class NestedVisibility1675Test < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(name: "Hans Admin", password: "secretsecret")
    @mia  = create_human(name: "Mia Member", role: :member, password: "secretsecret")
    [@hans, @mia].each { |u| CapabilityDefaults.grant_full!(u) }

    @geheim = create_topic(creator: @hans, name: "Geheimprojekt Adler", slug: "adler-#{SecureRandom.hex(3)}")
    @task   = create_task(creator: @hans, title: "Adler Startrampe", status: :open, skip_default_assignee: true)
    TaskTopic.create!(task: @task, topic: @geheim, position: 1)
    @ki = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Adler Dossier", item_type: :note,
                                file_path: "x/adler-#{SecureRandom.hex(3)}.md", content_hash: "h",
                                body: "Streng geheim", creator: @hans, published_at: Time.current)
    KnowledgeItemTopic.create!(knowledge_item_uuid: @ki.uuid, topic: @geheim)
    @antwort = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: nil, item_type: :reply,
                                     parent_type: "Task", parent_id_int: @task.id,
                                     file_path: "x/r-#{SecureRandom.hex(3)}.md", content_hash: "h",
                                     body: "Startfenster ist der 3. Oktober", creator: @hans,
                                     published_at: Time.current)

    @mias_thema = create_topic(creator: @mia, name: "Mias Thema", slug: "mia-#{SecureRandom.hex(3)}")
    @mias_task  = create_task(creator: @mia, title: "Mias Aufgabe", status: :open, skip_default_assignee: true)
  end

  def login!(user)
    post "/login", params: { email: user.email, password: "secretsecret" }
    assert_response :redirect
  end

  def zaehlerstand
    { antworten: KnowledgeItem.unscoped.where(item_type: :reply).count,
      task_topics: TaskTopic.count, ki_topics: KnowledgeItemTopic.count,
      taggings: Tagging.count, task_mentions: TaskMention.count,
      ki_mentions: KnowledgeItemMention.count, abhaengigkeiten: TaskDependency.count,
      unteraufgaben: Task.where.not(parent_id: nil).count, anhaenge: TaskAttachment.count }
  end

  # ── Fremdes ist unter KEINER Unter-Adresse zu lesen ─────────────────────

  test "member liest nichts Fremdes ueber die Unter-Adressen" do
    login!(@mia)
    ["/tasks/#{@task.id}/replies",
     "/knowledge_items/#{@ki.uuid}/replies",
     "/knowledge_items/#{@ki.uuid}/history",
     "/knowledge_items/#{@ki.uuid}/backlinks"].each do |pfad|
      get pfad
      assert_response :not_found, "#{pfad} verrät Fremdes (Status #{response.status})"
    end
  end

  # ── … und unter keiner zu ändern ────────────────────────────────────────

  SCHREIBVERSUCHE = [
    [:post, "/tasks/%{task}/replies",      { body: "Mia war hier" }],
    [:post, "/tasks/%{task}/tags",         { tag: "gekapert" }],
    [:post, "/tasks/%{task}/topics",       { topic_id: "%{mias_thema}" }],
    [:post, "/tasks/%{task}/mentions",     { mentioned_uuid: "%{ki_eigen}", kind: "knowledge" }],
    [:post, "/tasks/%{task}/subtasks",     { create_with: "Mias Unteraufgabe" }],
    [:post, "/tasks/%{task}/dependencies", { predecessor_id: "%{mias_task}" }],
    [:post, "/knowledge_items/%{ki}/replies",  { body: "Mia war hier" }],
    [:post, "/knowledge_items/%{ki}/tags",     { tag: "gekapert" }],
    [:post, "/knowledge_items/%{ki}/topics",   { topic_id: "%{mias_thema}" }],
    [:post, "/knowledge_items/%{ki}/task_mentions", { task_id: "%{mias_task}" }],
    [:post, "/knowledge_items/%{ki}/mentions", { mentioned_uuid: "%{ki_eigen}" }],
    [:post, "/tasks/%{task}/comments",     { task_comment: { body: "Mia war hier" } }],
    [:post, "/knowledge_items/%{ki}/ensure_anchor", { block_index: 0 }],
    [:post, "/knowledge_items/%{ki}/restore_version", { sha: "deadbeef" }],
    [:delete, "/tasks/%{task}/topics/%{geheim}", {}],
    [:delete, "/knowledge_items/%{ki}/topics/%{geheim}", {}]
  ].freeze

  def fuelle(wert, werte)
    case wert
    when String then format(wert, werte)
    when Hash   then wert.transform_values { |v| fuelle(v, werte) }
    else wert
    end
  end

  test "member aendert nichts Fremdes ueber die Unter-Adressen" do
    eigen = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Mias Notiz", item_type: :note,
                                  file_path: "x/mia-#{SecureRandom.hex(3)}.md", content_hash: "h",
                                  body: "x", creator: @mia, published_at: Time.current)
    werte = { task: @task.id, ki: @ki.uuid, mias_thema: @mias_thema.slug, mias_task: @mias_task.id,
              ki_eigen: eigen.uuid, geheim: @geheim.slug }
    login!(@mia)
    vorher = zaehlerstand

    SCHREIBVERSUCHE.each do |verb, pfad, params|
      url = fuelle(pfad, werte)
      send(verb, url, params: fuelle(params, werte))
      assert_response :not_found, "#{verb.upcase} #{url} kam durch (Status #{response.status})"
    end

    assert_equal vorher, zaehlerstand, "irgendein Schreibversuch hat etwas hinterlassen"
    assert_equal [@geheim.id], @task.reload.topic_ids, "die Aufgabe hängt weiter nur am geheimen Thema"
    refute Task.visible_to(@mia).exists?(@task.id), "Mia hat sich die Aufgabe nicht sichtbar gemacht"
  end

  # ── Sichtbar ≠ schreibbar ───────────────────────────────────────────────

  test "betrachter liest die Antworten, schreibt aber keine; bearbeiter schon" do
    m = TopicMembership.create!(topic: @geheim, actor: @mia, role: :viewer)
    login!(@mia)

    get "/tasks/#{@task.id}/replies"
    assert_response :success
    assert_includes response.body, "Startfenster"

    assert_no_difference -> { KnowledgeItem.unscoped.where(item_type: :reply).count } do
      post "/tasks/#{@task.id}/replies", params: { body: "Betrachter schreibt" }
    end
    assert_response :forbidden

    assert_no_difference -> { TaskTopic.count } do
      post "/tasks/#{@task.id}/topics", params: { topic_id: @mias_thema.slug }
    end
    assert_response :forbidden

    m.update!(role: :editor)
    assert_difference -> { KnowledgeItem.unscoped.where(item_type: :reply).count }, 1 do
      post "/tasks/#{@task.id}/replies", params: { body: "Bearbeiterin schreibt" }
    end
  end

  # ── Das Ziel einer Verknüpfung muss genauso sichtbar sein ───────────────

  test "member verknuepft Eigenes nicht mit Fremdem, das er nicht sieht" do
    login!(@mia)

    post "/tasks/#{@mias_task.id}/dependencies", params: { predecessor_id: @task.id }
    refute TaskDependency.exists?(successor_id: @mias_task.id), "fremde Aufgabe als Vorgänger verknüpft"

    post "/tasks/#{@mias_task.id}/topics", params: { topic_id: @geheim.slug }
    refute TaskTopic.exists?(task_id: @mias_task.id, topic_id: @geheim.id),
           "eigene Aufgabe in ein fremdes, unsichtbares Thema gehängt"

    post "/tasks/#{@mias_task.id}/subtasks", params: { child_id: @task.id }
    assert_nil @task.reload.parent_id, "fremde Aufgabe als Unteraufgabe vereinnahmt"
  end

  # ── Admin: unverändert ──────────────────────────────────────────────────

  test "admin arbeitet weiter ueber alle Unter-Adressen" do
    login!(@hans)
    get "/tasks/#{@task.id}/replies"
    assert_response :success
    assert_difference -> { KnowledgeItem.unscoped.where(item_type: :reply).count }, 1 do
      post "/tasks/#{@task.id}/replies", params: { body: "Admin schreibt" }
    end
    get "/knowledge_items/#{@ki.uuid}/history"
    assert_includes [200, 302], response.status
  end
end
