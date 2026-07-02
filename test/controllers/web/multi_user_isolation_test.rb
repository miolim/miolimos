require "test_helper"

# #602 S1: DAS Sicherheitsnetz der Multi-User-Sichtbarkeit (Pendant zum
# Portal-Isolations-Test #536). Kernsatz: ein Mitglied (role=member) sieht
# NUR (a) Topics, in denen es Mitglied ist, (b) intern Öffentliches,
# (c) Eigenes — unter keiner URL etwas anderes. Admins sehen alles
# (Bestand vor Multi-User bleibt unverändert).
class MultiUserIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(name: "Hans Admin", password: "secretsecret")              # admin
    @mia  = create_human(name: "Mia Member", role: :member, password: "secretsecret")
    %w[Task Topic KnowledgeItem Communication Awaiting InboxItem Document
       Event TimeEntry Search Dashboard WorkNode TopicTree Actor].each do |rt|
      grant(@hans, rt, %w[read create update delete])
      grant(@mia,  rt, %w[read create update delete])
    end

    # Geheimes Topic von Hans — Mia ist KEIN Mitglied.
    @geheim = create_topic(creator: @hans, name: "Geheimprojekt Adler", slug: "geheim-adler-#{SecureRandom.hex(3)}")
    @geheim_task = create_task(creator: @hans, title: "Adler Startrampe bauen",
                               status: :open, skip_default_assignee: true)
    TaskTopic.create!(task: @geheim_task, topic: @geheim, position: 1)
    @geheim_ki = ki!("Adler Geheimdossier")
    KnowledgeItemTopic.create!(knowledge_item_uuid: @geheim_ki.uuid, topic: @geheim)
    @geheim_awaiting = Awaiting.create!(creator: @hans, title: "Adler Rückmeldung", status: :open, follow_up_at: 1.week.from_now)
    AwaitingTopic.create!(awaiting: @geheim_awaiting, topic: @geheim)
    @geheim_doc   = Document.create!(kind: :brief, status: :entwurf, topic_id: @geheim.id, creator: @hans)
    @geheim_event = Event.create!(title: "Adler Kickoff", starts_at: Date.current.beginning_of_month + 14.days,  # sicher im angezeigten Monat
                                  topic_id: @geheim.id, creator: @hans)

    # Privates Objekt ohne Topic — sieht nur der Ersteller (+ Admins).
    @privat_task = create_task(creator: @hans, title: "Hans Privatnotiz Task",
                               status: :open, skip_default_assignee: true)

    # Intern öffentliches Topic — sehen ALLE internen Nutzer.
    @glossar = create_topic(creator: @hans, name: "Glossar Allgemein", slug: "glossar-#{SecureRandom.hex(3)}")
    @glossar.update!(visibility: :internal_public)
    @glossar_ki = ki!("Glossar Grundbegriffe")
    KnowledgeItemTopic.create!(knowledge_item_uuid: @glossar_ki.uuid, topic: @glossar)
  end

  def ki!(title)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title, item_type: :note,
                          file_path: "x/#{title.parameterize}.md", content_hash: "h",
                          body: "Inhalt #{title}", creator: @hans,
                          published_at: Time.current)
  end

  def login!(user)
    post "/login", params: { email: user.email, password: "secretsecret" }
    assert_response :redirect
  end

  # ── Member ohne Mitgliedschaft: sieht NICHTS vom Geheimprojekt ──────────

  test "member sieht fremdes Topic unter keiner Liste/Suche/Detail-URL" do
    login!(@mia)

    get "/topics/list_card"
    assert_response :success
    refute_includes response.body, "Geheimprojekt Adler"

    get "/topics/suggest", params: { q: "Geheim" }
    assert_response :success
    refute_includes response.body, "Geheimprojekt"

    get "/topics/#{@geheim.slug}"
    assert_response :not_found
  end

  test "member sieht fremde Tasks nicht (Liste, Suggest, Detail, Suche)" do
    login!(@mia)

    get "/tasks/list_card"
    assert_response :success
    refute_includes response.body, "Adler Startrampe"

    get "/tasks/suggest", params: { q: "Adler" }
    assert_response :success
    refute_includes response.body, "Adler Startrampe"

    get "/tasks/#{@geheim_task.id}/card"
    assert_response :not_found

    get "/search", params: { q: "Startrampe" }
    assert_response :success
    refute_includes response.body, "Adler Startrampe"
  end

  test "member sieht fremde KIs nicht (Suggest, Detail, Suche)" do
    login!(@mia)

    get "/knowledge_items/suggest", params: { q: "Geheimdossier" }
    assert_response :success
    refute_includes response.body, "Geheimdossier"

    get "/knowledge_items/#{@geheim_ki.uuid}/card"
    assert_response :not_found

    # Achtung: das Suchfeld echot die Anfrage — geprüft wird der TITEL.
    get "/search", params: { q: "Geheimdossier" }
    assert_response :success
    refute_includes response.body, "Adler Geheimdossier"
  end

  test "member sieht fremde Awaitings/Dokumente/Events/Privates nicht" do
    login!(@mia)

    get "/awaitings", params: {}
    assert_response :success
    refute_includes response.body, "Adler Rückmeldung"

    get "/documents/#{@geheim_doc.id}/card"
    assert_response :not_found

    # Kalender-Listen-Blade (lädt Events + Meilensteine der Periode).
    get "/calendar/list_card"
    assert_response :success
    refute_includes response.body, "Adler Kickoff"

    # Privates (Task ohne Topic, Ersteller Hans).
    get "/tasks/#{@privat_task.id}/card"
    assert_response :not_found
  end

  test "member: Stack-Restore lässt unsichtbare Blades leise raus" do
    login!(@mia)
    get "/tasks", params: { stack: "list:tasks,task:#{@geheim_task.id}" }
    assert_response :success
    refute_includes response.body, "Adler Startrampe"
  end

  # ── Mitgliedschaft schaltet frei ─────────────────────────────────────────

  test "membership macht Topic samt Inhalten sichtbar" do
    TopicMembership.create!(topic: @geheim, actor: @mia, role: :editor)
    login!(@mia)

    get "/topics/#{@geheim.slug}"
    assert_response :success

    get "/tasks/list_card"
    assert_includes response.body, "Adler Startrampe"

    get "/tasks/#{@geheim_task.id}/card"
    assert_response :success

    get "/knowledge_items/#{@geheim_ki.uuid}/card"
    assert_response :success

    get "/search", params: { q: "Geheimdossier" }
    assert_includes response.body, "Adler Geheimdossier"

    get "/calendar/list_card"
    assert_includes response.body, "Adler Kickoff"
  end

  test "intern öffentliches Topic ist ohne Mitgliedschaft sichtbar" do
    login!(@mia)

    get "/topics/#{@glossar.slug}"
    assert_response :success

    get "/knowledge_items/#{@glossar_ki.uuid}/card"
    assert_response :success
  end

  test "eigene Objekte sind ohne Topic sichtbar (Privates des Members)" do
    mia_task = create_task(creator: @mia, title: "Mias eigene Notiz",
                           status: :open, skip_default_assignee: true)
    login!(@mia)

    get "/tasks/#{mia_task.id}/card"
    assert_response :success

    get "/tasks/list_card"
    assert_includes response.body, "Mias eigene Notiz"
  end

  test "refs-blade rendert keine Inhalte unsichtbarer Wikilink-Ziele" do
    # Mias eigenes Topic mit einer KI, die auf Hans' Geheimdossier verlinkt —
    # das Refs-Blade rendert Ziel-VOLLTEXTE und darf Unsichtbares nicht zeigen.
    mia_topic = create_topic(creator: @mia, name: "Mias Thema", slug: "mias-thema-#{SecureRandom.hex(3)}")
    mia_ki = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Mias Notiz", item_type: :note,
                                   file_path: "x/mias-notiz.md", content_hash: "h",
                                   body: "Siehe [[Adler Geheimdossier]] und [[Glossar Grundbegriffe]].",
                                   creator: @mia, published_at: Time.current)
    KnowledgeItemTopic.create!(knowledge_item_uuid: mia_ki.uuid, topic: mia_topic)

    login!(@mia)
    get "/knowledge_items/#{mia_ki.uuid}/refs_card"
    assert_response :success
    refute_includes response.body, "Inhalt Adler Geheimdossier"   # fremd → raus
    assert_includes response.body, "Inhalt Glossar Grundbegriffe" # intern öffentlich → ok
  end

  # ── S2: Schreibrechte — sichtbar heißt nicht änderbar ───────────────────

  test "viewer-Mitglied liest, darf aber nicht ändern; editor darf" do
    m = TopicMembership.create!(topic: @geheim, actor: @mia, role: :viewer)
    login!(@mia)

    get "/tasks/#{@geheim_task.id}/card"
    assert_response :success

    patch "/tasks/#{@geheim_task.id}", params: { task: { title: "Umbenannt von Mia" } }
    assert_response :forbidden
    assert_equal "Adler Startrampe bauen", @geheim_task.reload.title

    patch "/topics/#{@geheim.slug}", params: { topic: { name: "Mias Adler" } }
    assert_response :forbidden
    assert_equal "Geheimprojekt Adler", @geheim.reload.name

    m.update!(role: :editor)
    patch "/tasks/#{@geheim_task.id}", params: { task: { title: "Umbenannt von Mia" } }
    assert_response :redirect   # HTML-Pfad redirectet nach Erfolg
    assert_equal "Umbenannt von Mia", @geheim_task.reload.title

    # #602 S3: Bearbeiter bearbeiten INHALTE — das Thema selbst bleibt tabu.
    patch "/topics/#{@geheim.slug}", params: { topic: { name: "Mias Adler" } }
    assert_response :forbidden

    # Verantwortliche dürfen das Thema verwalten.
    m.update!(role: :owner)
    patch "/topics/#{@geheim.slug}", params: { topic: { name: "Mias Adler" } }
    assert_response :redirect
    assert_equal "Mias Adler", @geheim.reload.name
  end

  test "intern öffentliches ist lesbar, aber ohne Mitgliedschaft nicht änderbar" do
    glossar_task = create_task(creator: @hans, title: "Glossar pflegen",
                               status: :open, skip_default_assignee: true)
    TaskTopic.create!(task: glossar_task, topic: @glossar, position: 1)
    login!(@mia)

    get "/tasks/#{glossar_task.id}/card"
    assert_response :success

    patch "/tasks/#{glossar_task.id}", params: { task: { title: "Kaputt" } }
    assert_response :forbidden
    assert_equal "Glossar pflegen", glossar_task.reload.title
  end

  test "eigene Objekte bleiben für den Member änderbar" do
    mia_task = create_task(creator: @mia, title: "Mias Task", status: :open,
                           skip_default_assignee: true)
    login!(@mia)
    patch "/tasks/#{mia_task.id}", params: { task: { title: "Mias Task v2" } }
    assert_response :redirect   # HTML-Pfad redirectet nach Erfolg
    assert_equal "Mias Task v2", mia_task.reload.title
  end

  test "Mitglieder verwalten dürfen nur Admins oder Verantwortliche" do
    TopicMembership.create!(topic: @geheim, actor: @mia, role: :editor)
    login!(@mia)

    extra = create_human(name: "Extra Nutzer", role: :member)
    post "/topics/#{@geheim.slug}/memberships", params: { actor_id: extra.id }
    assert_response :forbidden
    refute TopicMembership.exists?(topic: @geheim, actor: extra)

    TopicMembership.find_by(topic: @geheim, actor: @mia).update!(role: :owner)
    post "/topics/#{@geheim.slug}/memberships", params: { actor_id: extra.id }
    assert_response :success
    assert TopicMembership.exists?(topic: @geheim, actor: extra)
  end

  # ── S2: Live-Broadcasts erreichen nur Sichtberechtigte ──────────────────

  test "task-row-broadcasts gehen nur an Streams sichtberechtigter Nutzer" do
    # Titel-Update einer Geheim-Task: Hans' (Admin-)Stream bekommt die Row,
    # Mias Stream bleibt leer. (Globaler "tasks"-Stream existiert nicht mehr.)
    streams = capture_broadcasts_for([@hans, @mia]) do
      @geheim_task.update!(title: "Adler Startrampe v2")
    end
    assert streams[@hans.id].any? { |p| p.include?("Adler Startrampe v2") },
           "Admin-Stream muss die Row erhalten"
    assert streams[@mia.id].empty?, "Member ohne Sicht darf keine Row-Daten erhalten"

    # Mit Mitgliedschaft kommt die Row auch bei Mia an.
    TopicMembership.create!(topic: @geheim, actor: @mia, role: :viewer)
    streams = capture_broadcasts_for([@hans, @mia]) do
      @geheim_task.update!(title: "Adler Startrampe v3")
    end
    assert streams[@mia.id].any? { |p| p.include?("Adler Startrampe v3") }
  end

  # Fängt ActionCable-Broadcasts ab und ordnet sie den
  # "tasks_user_<id>"-Streams der übergebenen Nutzer zu.
  def capture_broadcasts_for(users)
    intercepted = []
    ActionCable.server.singleton_class.class_eval do
      alias_method :__orig_broadcast, :broadcast
      define_method(:broadcast) do |channel, payload, **kw|
        intercepted << [channel, payload]
        __orig_broadcast(channel, payload, **kw)
      end
    end
    yield
    users.to_h do |u|
      [u.id, intercepted.select { |c, _| c == "tasks_user_#{u.id}" }.map { |_, p| p.to_s }]
    end
  ensure
    ActionCable.server.singleton_class.class_eval do
      alias_method :broadcast, :__orig_broadcast
      remove_method :__orig_broadcast
    end
  end

  # ── S2: Kalender-Feed je Nutzer ──────────────────────────────────────────

  test "ICS-Feed ist nutzer-gescoped; alter globaler Token ist ungültig" do
    # Mias eigener Termin in ihrem Topic + Hans' Geheim-Termin.
    mia_topic = create_topic(creator: @mia, name: "Mias Feed-Thema", slug: "mias-feed-#{SecureRandom.hex(3)}")
    Event.create!(title: "Mias Termin", starts_at: 3.days.from_now,
                  topic_id: mia_topic.id, creator: @mia)

    get "/calendar/feed", params: { token: CalendarController.feed_token(@mia) }
    assert_response :success
    assert_includes response.body, "Mias Termin"
    refute_includes response.body, "Adler Kickoff"

    get "/calendar/feed", params: { token: CalendarController.feed_token(@hans) }
    assert_response :success
    assert_includes response.body, "Adler Kickoff"

    # Legacy-Token (vor S2: {scope:"all"}) → 403.
    legacy = CalendarController.feed_verifier.generate({ scope: "all" })
    get "/calendar/feed", params: { token: legacy }
    assert_response :forbidden

    get "/calendar/feed", params: { token: "quatsch" }
    assert_response :forbidden
  end

  # ── S2: Konto-Inhaber sieht seine Mails ──────────────────────────────────

  test "communications: Konto-Inhaber sieht eigenes Postfach, fremde nicht" do
    cred_hans = OauthCredential.create!(actor: @hans, provider: "google",
                                        email_address: "hans-#{SecureRandom.hex(3)}@mail.local")
    cred_mia  = OauthCredential.create!(actor: @mia, provider: "google",
                                        email_address: "mia-#{SecureRandom.hex(3)}@mail.local")
    mail_hans = Email.create!(external_id: "iso-#{SecureRandom.hex(4)}", direction: :inbound,
                              subject: "Hans Geheimmail", sent_at: Time.current,
                              oauth_credential: cred_hans)
    mail_mia  = Email.create!(external_id: "iso-#{SecureRandom.hex(4)}", direction: :inbound,
                              subject: "Mias Kontomail", sent_at: Time.current,
                              oauth_credential: cred_mia)

    assert_includes Communication.visible_to(@mia), mail_mia
    refute_includes Communication.visible_to(@mia), mail_hans
    assert_includes Communication.visible_to(@hans), mail_hans  # Admin

    login!(@mia)
    get "/communications/#{mail_mia.id}/card"
    assert_response :success
    get "/communications/#{mail_hans.id}/card"
    assert_response :not_found

    # Fremdes Konto weder syncen noch trennen — auch MIT Capability
    # (das Capability-Gate regelt das WAS, der Owner-Guard das WESSEN).
    grant(@mia, "OauthCredential", %w[read create update delete])
    delete "/settings/accounts/#{cred_hans.id}"
    assert_response :not_found
    assert OauthCredential.exists?(cred_hans.id)
  end

  # ── S3: Gast — nur lesen in eingeladenen Themen ──────────────────────────

  test "gast liest in seinen Themen, schreibt aber nie — Eigenes bleibt seins" do
    gast = create_human(name: "Gabi Gast", role: :guest, password: "secretsecret")
    %w[Task Topic KnowledgeItem].each { |rt| grant(gast, rt, %w[read create update delete]) }
    # Selbst als „Verantwortlicher" eingetragen: Gast bleibt read-only.
    TopicMembership.create!(topic: @geheim, actor: gast, role: :owner)
    login!(gast)

    get "/tasks/#{@geheim_task.id}/card"
    assert_response :success

    patch "/tasks/#{@geheim_task.id}", params: { task: { title: "Gast war hier" } }
    assert_response :forbidden
    assert_equal "Adler Startrampe bauen", @geheim_task.reload.title

    patch "/topics/#{@geheim.slug}", params: { topic: { name: "Gastthema" } }
    assert_response :forbidden

    # Mitglieder verwalten darf der Gast trotz owner-Eintrag nicht.
    extra = create_human(name: "Extra", role: :member)
    post "/topics/#{@geheim.slug}/memberships", params: { actor_id: extra.id }
    assert_response :forbidden

    # Eigene Objekte bleiben editierbar.
    own = create_task(creator: gast, title: "Gasts Notiz", status: :open,
                      skip_default_assignee: true)
    patch "/tasks/#{own.id}", params: { task: { title: "Gasts Notiz v2" } }
    assert_response :redirect
    assert_equal "Gasts Notiz v2", own.reload.title
  end

  # ── S3: Mitgliedschaft vererbt sich an Sub-Topics ────────────────────────

  test "membership im Eltern-Thema öffnet den Teilbaum samt Rollen" do
    sub = create_topic(creator: @hans, name: "Adler Sub", slug: "adler-sub-#{SecureRandom.hex(3)}")
    sub.update!(parent_topic: @geheim)
    sub_task = create_task(creator: @hans, title: "Sub-Task Adler",
                           status: :open, skip_default_assignee: true)
    TaskTopic.create!(task: sub_task, topic: sub, position: 1)

    # Ohne Mitgliedschaft: nichts.
    login!(@mia)
    get "/topics/#{sub.slug}"
    assert_response :not_found

    # Editor im PARENT: Sub-Topic + Inhalt sichtbar und editierbar …
    TopicMembership.create!(topic: @geheim, actor: @mia, role: :editor)
    get "/topics/#{sub.slug}"
    assert_response :success
    get "/tasks/#{sub_task.id}/card"
    assert_response :success
    patch "/tasks/#{sub_task.id}", params: { task: { title: "Sub-Task v2" } }
    assert_response :redirect
    assert_equal "Sub-Task v2", sub_task.reload.title

    # … aber das Sub-THEMA verwalten darf der Editor nicht.
    patch "/topics/#{sub.slug}", params: { topic: { name: "Subraub" } }
    assert_response :forbidden

    # Owner im Parent verwaltet auch das Sub-Thema.
    TopicMembership.find_by(topic: @geheim, actor: @mia).update!(role: :owner)
    patch "/topics/#{sub.slug}", params: { topic: { name: "Sub umbenannt" } }
    assert_response :redirect
    assert_equal "Sub umbenannt", sub.reload.name
  end

  # ── S3: „Als X ansehen" — Read-only-Vorschau ─────────────────────────────

  test "admin sieht in der Vorschau exakt Mias Sicht, read-only, beendbar" do
    login!(@hans)

    post "/settings/users/#{@mia.id}/preview"
    assert_response :redirect

    # Sicht = Mia: Geheimes ist weg.
    get "/tasks/#{@geheim_task.id}/card"
    assert_response :not_found
    get "/dashboard"
    assert_includes response.body, "Du siehst miolimOS als Mia Member"

    # Schreiben ist geblockt — auch Eigenes von Mia.
    mia_task = create_task(creator: @mia, title: "Mias Vorschau-Task",
                           status: :open, skip_default_assignee: true)
    patch "/tasks/#{mia_task.id}", params: { task: { title: "Verändert" } }
    assert_response :redirect   # redirect_back mit Alert
    assert_equal "Mias Vorschau-Task", mia_task.reload.title

    # Beenden stellt die Admin-Sicht wieder her.
    delete "/preview"
    assert_response :redirect
    get "/tasks/#{@geheim_task.id}/card"
    assert_response :success
  end

  test "nur Admins starten die Vorschau" do
    login!(@mia)
    post "/settings/users/#{@hans.id}/preview"
    assert_response :forbidden
    get "/tasks/#{@geheim_task.id}/card"
    assert_response :not_found   # weiterhin Mias eigene Sicht
  end

  # ── Admin: Bestand unverändert ───────────────────────────────────────────

  test "admin sieht weiterhin alles" do
    login!(@hans)

    get "/topics/#{@geheim.slug}"
    assert_response :success

    get "/tasks/list_card"
    assert_includes response.body, "Adler Startrampe"

    get "/search", params: { q: "Geheimdossier" }
    assert_includes response.body, "Adler Geheimdossier"
  end

  # ── Rollen-Schutz: Member kann sich nicht selbst befördern ──────────────

  test "member kann seine Rolle nicht selbst auf admin setzen" do
    login!(@mia)
    patch "/settings/users/#{@mia.id}", params: { human_actor: { name: @mia.name, email: @mia.email, role: "admin" } }
    assert_equal "member", @mia.reload.role
  end
end
