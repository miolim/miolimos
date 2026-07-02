require "application_system_test_case"

# #206 Phase 2: Sicherheitsnetz fuer blade_stack_controller.js — speziell
# fuer die Persistenz-Logik (snapshotToHistory + restoreLastFromHistoryIfAny),
# weil genau die als naechstes in ein eigenes Modul extrahiert wird.
# Diese Tests bleiben gruen vor wie nach dem Refactor.
class BladeStackTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "Task", %w[read])

    @tmp_base = Pathname.new(Dir.mktmpdir("miolim-systest-"))
    @original_base = FileProxy::BASE_PATH
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @tmp_base)

    @items = %w[alpha beta gamma].map do |name|
      uuid = SecureRandom.uuid
      rel  = "knowledge/notes/#{name}.md"
      FileUtils.mkdir_p(@tmp_base.join("knowledge/notes"))
      File.write(@tmp_base.join(rel),
        "---\nid: #{uuid}\ntype: note\n---\n\n# #{name.capitalize}\n\nInhalt von #{name}.\n")
      KnowledgeItem.create!(
        uuid: uuid, title: name.capitalize, item_type: "note",
        creator: @hans, file_path: rel, content_hash: "h-#{name}"
      )
    end
    @alpha, @beta, @gamma = @items

    login_as(@hans)
  end

  teardown do
    if @original_base
      FileProxy.send(:remove_const, :BASE_PATH)
      FileProxy.const_set(:BASE_PATH, @original_base)
    end
    FileUtils.remove_entry(@tmp_base) if @tmp_base&.exist?
  end

  # ─── Mount ─────────────────────────────────────────────────────────

  test "Initial-Stack: ?stack=uuid rendert die KI als Card und mountet Controller" do
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    assert page.has_css?("[data-controller~='blade-stack']"),
           "blade-stack Controller muss am Container haengen"
    assert page.has_css?("article.stack-card[data-uuid='#{@alpha.uuid}']"),
           "Alpha-Card muss im Stack sichtbar sein"
  end

  test "Initial-Stack: mehrere UUIDs erzeugen mehrere Cards in Reihenfolge" do
    visit "/knowledge_items?stack=#{@alpha.uuid},#{@beta.uuid},#{@gamma.uuid}"
    uuids = page.all("article.stack-card[data-uuid]").map { |el| el["data-uuid"] }
    assert_equal [@alpha.uuid, @beta.uuid, @gamma.uuid], uuids.first(3)
  end

  # ─── Persistenz: snapshotToHistory ─────────────────────────────────

  test "snapshotToHistory schreibt den aktuellen Trail in localStorage" do
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller~='blade-stack']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
      ctrl.snapshotToHistory()
    JS
    raw = page.evaluate_script("localStorage.getItem('knowledge.stack.history')")
    assert raw.is_a?(String), "History muss in localStorage stehen"
    history = JSON.parse(raw)
    assert_kind_of Array, history
    assert_operator history.size, :>=, 1
    last_trail = history.first["trail"].last
    assert_includes last_trail, @alpha.uuid
    assert_equal false, !!history.first["pinned"], "Frischer Snapshot ist nicht pinned"
  end

  test "snapshotToHistory ueberschreibt bestehenden Eintrag mit derselben Komposition" do
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    2.times do
      page.execute_script(<<~JS)
        const el = document.querySelector("[data-controller~='blade-stack']")
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
        ctrl.snapshotToHistory()
      JS
    end
    history = JSON.parse(page.evaluate_script("localStorage.getItem('knowledge.stack.history')"))
    same_composition = history.select { |h| h["trail"].last.join(",") == @alpha.uuid }
    assert_equal 1, same_composition.size,
                 "Wiederholter Snapshot mit derselben Final-Komposition darf nicht duplizieren"
  end

  # ─── Persistenz: restoreLastFromHistoryIfAny ───────────────────────

  test "restoreLastFromHistoryIfAny rekonstruiert Stack aus localStorage" do
    # Schritt 1: Stack befuellen + Snapshot. #434/#564: der Verlaufs-Bucket
    # haengt am ERSTEN Blade (list:… = eigener Bucket). Snapshot und Restore
    # muessen im selben Bucket landen — darum startet der Stack hier mit
    # demselben Listen-Blade wie der Restore-Besuch in Schritt 2.
    visit "/knowledge_items?stack=list:knowledge_items,#{@beta.uuid},#{@gamma.uuid}"
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller~='blade-stack']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
      ctrl.snapshotToHistory()
    JS

    # Schritt 2: nur mit Listen-Blade rein, kein Detail. #163 Phase 6c:
    # auto-restore beim Page-Load greift nur, wenn keine Server-Cards
    # angeliefert wurden — list:knowledge_items zaehlt schon als Card.
    # Wir triggern den Restore daher explizit per JS (entspricht der
    # Verlauf-Drawer-Interaktion durch den User).
    visit "/knowledge_items?stack=list:knowledge_items"
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-controller~='blade-stack']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
      ctrl.restoreLastFromHistoryIfAny()
    JS

    # Capybara wartet bis zu 5s; restore ist async (fetch je Card).
    assert page.has_css?("article.stack-card[data-uuid='#{@beta.uuid}']"),
           "Beta-Card muss aus History wiederhergestellt sein"
    assert page.has_css?("article.stack-card[data-uuid='#{@gamma.uuid}']"),
           "Gamma-Card muss aus History wiederhergestellt sein"
  end

  # ─── Persistenz: HISTORY_MAX ───────────────────────────────────────

  test "trimHistory kappt nicht-pinned-Eintraege auf HISTORY_MAX (=10)" do
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    # Schreibe 12 verschiedene (nicht-pinned) Eintraege via direkte
    # localStorage-Befuellung, dann ein snapshotToHistory zum Triggern
    # von trimHistory.
    fake_entries = (1..12).map do |i|
      { trail: [["fake-uuid-#{i}"]], current: 0, pinned: false,
        savedAt: (Time.current - i.minutes).iso8601 }
    end
    page.execute_script(<<~JS, fake_entries.to_json)
      localStorage.setItem("knowledge.stack.history", arguments[0])
      const el = document.querySelector("[data-controller~='blade-stack']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
      ctrl.snapshotToHistory()  // triggert trimHistory beim Schreiben
    JS
    history = JSON.parse(page.evaluate_script("localStorage.getItem('knowledge.stack.history')"))
    non_pinned = history.reject { |h| h["pinned"] }
    # Plus dem aktuellen Snapshot von alpha (=11); trimHistory haelt
    # HISTORY_MAX=10 non-pinned, aber der aktuelle ist immer dabei.
    # Daher: <= 11.
    assert_operator non_pinned.size, :<=, 11,
                    "Non-pinned Eintraege duerfen nicht ungebremst wachsen"
  end

  # ─── Phase 2: Cross-Entity-Blades (Task) ───────────────────────────

  # ─── Phase 3: Listen-Kollaps ───────────────────────────────────────

  # #224 6f-1: Auto-Collapse von Listen-Blades ist raus. Stattdessen
  # ersetzt 6f-2 den Sub-Stack (zwischen Listen-Blade und naechstem
  # list:*-Blade) durch die neue Detail-Card. Test reflektiert diese
  # neue Semantik.
  test "openFromList ersetzt den Sub-Stack hinter der Listen-Blade" do
    visit "/knowledge_items"
    list_card_sel = "article.stack-card[data-uuid='list:knowledge_items']"
    assert page.has_css?(list_card_sel)

    # Erste Item-Auswahl: beta-Card kommt rechts der Listen-Card.
    page.execute_script(<<~JS, @beta.uuid, list_card_sel)
      const el = document.querySelector("[data-controller~='blade-stack']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
      const fake = document.createElement("a")
      fake.dataset.targetUuid = arguments[0]
      const sourceList = document.querySelector(arguments[1])
      sourceList.appendChild(fake)
      ctrl.openFromList({ preventDefault() {}, currentTarget: fake, target: fake })
    JS
    assert page.has_css?("article.stack-card[data-uuid='#{@beta.uuid}']")
    # Listen-Blade bleibt offen (kein Auto-Collapse mehr).
    collapsed = page.evaluate_script("document.querySelector(#{list_card_sel.inspect})?.dataset.collapsed")
    refute_equal "true", collapsed, "Listen-Blade darf nicht mehr auto-collapsen"

    # Zweite Item-Auswahl: gamma ersetzt beta im Sub-Stack.
    page.execute_script(<<~JS, @gamma.uuid, list_card_sel)
      const el = document.querySelector("[data-controller~='blade-stack']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
      const fake = document.createElement("a")
      fake.dataset.targetUuid = arguments[0]
      const sourceList = document.querySelector(arguments[1])
      sourceList.appendChild(fake)
      ctrl.openFromList({ preventDefault() {}, currentTarget: fake, target: fake })
    JS
    assert page.has_css?("article.stack-card[data-uuid='#{@gamma.uuid}']")
    refute page.has_css?("article.stack-card[data-uuid='#{@beta.uuid}']"),
           "Beta-Card muss durch Sub-Stack-Ersatz weg sein"
  end

  test "openTask appended eine Task-Card als Blade im bestehenden Stack" do
    grant(@hans, "Task", %w[read create])
    task = Task.create!(title: "Blade-Test-Aufgabe", creator: @hans, assignee: @hans,
                        description: "Pruefe Cross-Entity-Stack")
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    page.execute_script(<<~JS, task.id)
      const el = document.querySelector("[data-controller~='blade-stack']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
      const fake = document.createElement("a")
      fake.dataset.taskId = arguments[0]
      ctrl.openTask({ preventDefault() {}, stopPropagation() {}, currentTarget: fake })
    JS
    assert page.has_css?("article.stack-card[data-uuid='task:#{task.id}']"),
           "Task-Blade muss nach openTask im Stack sein"
    assert page.has_text?("Blade-Test-Aufgabe")
  end

  # ─── Phase 4: Topic-Blades + Sidebar-Plus ──────────────────────────

  # #801: /topics/:slug/card rendert inzwischen das Topic-LISTEN-Blade —
  # die Card im DOM trägt data-uuid "list:topic:<slug>", nicht "topic:<slug>".
  test "openTopic appended eine Topic-Card als Blade" do
    topic = Topic.create!(name: "Blade-Phase4-Topic", slug: "blade-phase4-#{SecureRandom.hex(2)}",
                          creator: @hans)
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    page.execute_script(<<~JS, topic.slug)
      const el = document.querySelector("[data-controller~='blade-stack']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
      const fake = document.createElement("a")
      fake.dataset.topicSlug = arguments[0]
      ctrl.openTopic({ preventDefault() {}, stopPropagation() {}, currentTarget: fake })
    JS
    assert page.has_css?("article.stack-card[data-uuid='list:topic:#{topic.slug}']"),
           "Topic-Blade muss nach openTopic im Stack sein"
    assert page.has_text?("Blade-Phase4-Topic")
  end

  # Plus-Icon im Sidebar dispatcht ein globales blade-stack:append-Event,
  # weil die Sidebar ein separater DOM-Subtree ist (kein Stimulus-Ancestor
  # des blade-stack). blade-stack hoert auf window und appended.
  test "blade-link-Plus appendet Topic via globales Window-Event" do
    topic = Topic.create!(name: "Sidebar-Plus-Topic", slug: "sidebar-plus-#{SecureRandom.hex(2)}",
                          creator: @hans)
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    page.execute_script(<<~JS, topic.slug)
      window.dispatchEvent(new CustomEvent("blade-stack:append",
        { detail: { kind: "topic", id: arguments[0] } }))
    JS
    assert page.has_css?("article.stack-card[data-uuid='list:topic:#{topic.slug}']"),
           "Topic-Blade muss auch per globalem Append-Event landen"
    assert page.has_text?("Sidebar-Plus-Topic")
  end

  # has-blade-stack-Body-Klasse steuert die CSS-Sichtbarkeit der
  # Sidebar-Plus-Icons (.sidebar-blade-plus).
  test "body.has-blade-stack ist gesetzt wenn Seite einen Blade-Stack hat" do
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    klass = page.evaluate_script("document.body.classList.contains('has-blade-stack')")
    assert_equal true, klass, "body muss has-blade-stack haben, wenn blade-stack im DOM ist"
  end

  # #224 6f-1: Spine-Single-Click = Focus (NICHT mehr Toggle). Doppel-
  # Klick = Toggle. Wir testen explizit Single (kein Toggle) + Double
  # (Toggle ueber Controller-Action, weil dispatchen von echtem
  # dblclick-Event in Capybara umstaendlich ist).
  test "Spine-Klick fokussiert ohne zu togglen, dblclick toggelt" do
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    page.execute_script(<<~JS)
      const card = document.querySelector(".stack-card[data-uuid='#{@alpha.uuid}']")
      const spine = card.querySelector(".stack-spine")
      spine.click()
    JS
    val = page.evaluate_script("document.querySelector(\".stack-card[data-uuid='#{@alpha.uuid}']\").dataset.collapsed")
    refute_equal "true", val, "Single-Spine-Klick darf NICHT collapsen"

    # Doppelklick simulieren — direkt toggleCollapse aufrufen, das war
    # eh die alte Single-Click-Semantik.
    page.execute_script(<<~JS)
      const card = document.querySelector(".stack-card[data-uuid='#{@alpha.uuid}']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("[data-controller~='blade-stack']"), "blade-stack")
      ctrl.toggleCollapse({ currentTarget: card.querySelector(".stack-spine"),
                            preventDefault: () => {} })
    JS
    val2 = page.evaluate_script("document.querySelector(\".stack-card[data-uuid='#{@alpha.uuid}']\").dataset.collapsed")
    assert_equal "true", val2, "toggleCollapse muss collapsed setzen"
  end

  # #224 6f-1: KEIN Auto-Collapse mehr (war #163 Phase 6b — Hans hat das
  # explizit revidiert, „hat sich aus verwirrend herausgestellt").
  test "Listen-Blade bleibt nach Item-Klick offen" do
    grant(@hans, "Task", %w[read create])
    task = Task.create!(title: "Auto-Collapse-Probe", creator: @hans, assignee: @hans)
    visit "/dashboard?stack=list:tasks"
    page.execute_script(<<~JS, task.id)
      const list = document.querySelector("article.stack-card[data-uuid='list:tasks']")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("[data-controller~='blade-stack']"), "blade-stack")
      const fake = document.createElement("a")
      fake.dataset.taskId = arguments[0]
      list.appendChild(fake)
      ctrl.openTask({ preventDefault() {}, stopPropagation() {}, currentTarget: fake, target: fake })
    JS
    assert page.has_css?("article.stack-card[data-uuid='task:#{task.id}']")
    collapsed = page.evaluate_script("document.querySelector(\"article.stack-card[data-uuid='list:tasks']\").dataset.collapsed")
    refute_equal "true", collapsed, "Listen-Blade darf NICHT mehr auto-collapsen"
  end

  # #163 Phase 6a: Plus-Icon (blade-stack:append mit forceNew=true)
  # erlaubt mehrere Instanzen desselben Items im Stack.
  test "Plus-Icon-Event appendet trotz bestehender Instanz eine zweite" do
    visit "/knowledge_items?stack=#{@alpha.uuid}"
    # Erste Instanz schon im DOM (server-rendered). Plus-Event simulieren:
    page.execute_script(<<~JS)
      window.dispatchEvent(new CustomEvent("blade-stack:append",
        { detail: { kind: "topic", id: "fake-#{SecureRandom.hex(2)}" } }))
    JS
    # Anderes Beispiel: dispatch fuer eine existierende KI-UUID koennen
    # wir nicht direkt testen, weil das Window-Event nur fuer non-KI-Kinds
    # umgemappt ist. Wir pruefen stattdessen den client-side
    # appendFromList-Pfad (Plus-Icon-Verhalten):
    page.execute_script(<<~JS, @alpha.uuid)
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("[data-controller~='blade-stack']"), "blade-stack")
      const fake = document.createElement("button")
      fake.dataset.targetUuid = arguments[0]
      ctrl.appendFromList({ preventDefault() {}, stopPropagation() {}, currentTarget: fake })
    JS
    # Capybara wait — appendCard ist async.
    assert page.has_css?(".stack-card[data-uuid='#{@alpha.uuid}']", count: 2),
           "appendFromList dupliziert die KI-Card jetzt"
  end

  # #163 Phase 5a-1: Server-Side restore von gemischten Stacks aus dem
  # ?stack=-Param. Vorher gingen nur KI-UUIDs durch; jetzt task:/topic:/
  # src:-Prefixe ebenfalls.
  test "Initial-Stack: gemischter ?stack mit KI + task + topic + src" do
    grant(@hans, "Task", %w[read])
    task  = Task.create!(title: "Mixed-Test", creator: @hans)
    topic = Topic.create!(name: "MixedTopic", slug: "mixed-#{SecureRandom.hex(2)}", creator: @hans)
    src   = Source.create!(title: "MixedSrc", slug: "msrc-#{SecureRandom.hex(2)}",
                           csl_type: "book", creator: @hans)
    stack = "#{@alpha.uuid},task:#{task.id},topic:#{topic.slug},src:#{src.slug}"
    visit "/knowledge_items?stack=#{stack}"
    assert page.has_css?("article.stack-card[data-uuid='#{@alpha.uuid}']"),     "KI-Blade serverseitig gerendert"
    assert page.has_css?("article.stack-card[data-uuid='task:#{task.id}']"),   "Task-Blade serverseitig gerendert"
    assert page.has_css?("article.stack-card[data-uuid='list:topic:#{topic.slug}']"),"Topic-Blade serverseitig gerendert"
    assert page.has_css?("article.stack-card[data-uuid='src:#{src.slug}']"),   "Source-Blade serverseitig gerendert"
  end
end
