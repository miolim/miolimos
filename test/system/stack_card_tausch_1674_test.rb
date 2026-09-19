require "application_system_test_case"

# #1674: Aus dem immoOS-Fork nach Upstream übernommene Stack-Regeln, die hier
# noch keinen eigenen Aufrufer haben — der Test ist deshalb ihr Vertrag:
#
#   blade-stack#oeffneStattdessen   Card an derselben Stelle durch eine andere
#                                   ersetzen (immoOS #1483)
#   refreshCard + data-own-width    eine selbstgeführte Breite übersteht den
#                                   Refresh (immoOS #1473)
#   blade-stack:relayout            Signal „bitte neu ausrichten" (immoOS #1097)
#   simple-tabs                     `initial`-Reiter und das Ereignis
#                                   simple-tabs:gewechselt (immoOS #1567, #1665)
class StackCardTausch1674Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update])
    @tasks = 3.times.map do |i|
      Task.create!(title: "Aufgabe #{i + 1}", creator: @hans, assignee: @hans, status: :open)
    end
    login_as(@hans)
  end

  def uuids
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#blade_stack_container .stack-card"))
           .map(c => c.dataset.uuid)
    JS
  end

  def id(task) = "task:#{task.id}"

  # Liste + Aufgabe 1 + Aufgabe 2 nebeneinander.
  def stapel_oeffnen
    page.driver.resize_window(1600, 900)
    visit "/tasks?stack=list:tasks,#{id(@tasks[0])},#{id(@tasks[1])}"
    assert_selector ".stack-card[data-uuid='#{id(@tasks[1])}']", wait: 10
    assert_equal ["list:tasks", id(@tasks[0]), id(@tasks[1])], uuids
  end

  # Hängt einen Knopf mit der Klick-Action in die Card — so, wie eine View ihn
  # später trüge.
  def tausch_knopf_in(card_uuid, ziel_uuid)
    page.execute_script(<<~JS, card_uuid, ziel_uuid)
      const card = document.querySelector(`.stack-card[data-uuid='${arguments[0]}']`)
      const b = document.createElement("button")
      b.id = "tausch_knopf"
      b.type = "button"
      b.textContent = "weiter"
      b.dataset.action = "click->blade-stack#oeffneStattdessen"
      b.dataset.targetUuid = arguments[1]
      b.style.cssText = "position:absolute;top:60px;left:60px;z-index:99"
      card.appendChild(b)
    JS
  end

  test "oeffneStattdessen: andere Card am selben Platz, gleich breit, ohne Sprung" do
    stapel_oeffnen
    breite_vorher = page.evaluate_script(
      "Math.round(document.querySelector(\".stack-card[data-uuid='#{id(@tasks[0])}']\").getBoundingClientRect().width)")
    tausch_knopf_in(id(@tasks[0]), id(@tasks[2]))
    scroll_vorher = page.evaluate_script("document.getElementById('blade_stack_container').scrollLeft")

    find("#tausch_knopf").click

    assert_selector ".stack-card[data-uuid='#{id(@tasks[2])}']", wait: 10
    assert_equal ["list:tasks", id(@tasks[2]), id(@tasks[1])], uuids,
                 "die neue Card steht am Platz der alten — nichts angehängt, nichts rechts davon entfernt"
    assert_equal breite_vorher,
                 page.evaluate_script(
                   "Math.round(document.querySelector(\".stack-card[data-uuid='#{id(@tasks[2])}']\").getBoundingClientRect().width)"),
                 "gleiche Breite am selben Platz — nichts ruckt"
    assert_equal scroll_vorher,
                 page.evaluate_script("document.getElementById('blade_stack_container').scrollLeft"),
                 "kein Scroll-Sprung"
    assert_includes CGI.unescape(page.current_url), id(@tasks[2]), "die Adresse kennt die neue Card"
  end

  test "oeffneStattdessen: ist das Ziel schon offen, wird gesprungen statt verdoppelt" do
    stapel_oeffnen
    tausch_knopf_in(id(@tasks[0]), id(@tasks[1]))

    find("#tausch_knopf").click

    assert_selector ".stack-card[data-uuid='#{id(@tasks[1])}'][data-active='true']", wait: 10
    assert_equal ["list:tasks", id(@tasks[0]), id(@tasks[1])], uuids, "keine zweite Kopie, die Quelle bleibt"
  end

  test "refreshCard: eine selbstgefuehrte Breite (data-own-width) uebersteht den Refresh" do
    stapel_oeffnen
    page.execute_script(<<~JS, id(@tasks[0]))
      const c = document.querySelector(`.stack-card[data-uuid='${arguments[0]}']`)
      c.dataset.ownWidth = "true"
      c.style.width = "641px"; c.style.maxWidth = "none"
      c.dataset.alteInstanz = "ja"
      const el = document.querySelector('[data-controller~="blade-stack"]')
      window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack").refreshCard(arguments[0])
    JS

    # Erst wenn die ALTE Instanz weg ist, hat der Refresh stattgefunden.
    assert_no_selector ".stack-card[data-alte-instanz='ja']", wait: 10
    frisch = ".stack-card[data-uuid='#{id(@tasks[0])}']"
    assert_selector "#{frisch}[data-own-width='true']", wait: 5
    assert_equal "641px", page.evaluate_script("document.querySelector(\"#{frisch}\").style.width")
  end

  test "blade-stack:relayout laesst den Stack neu ausrichten" do
    stapel_oeffnen
    gezaehlt = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="blade-stack"]')
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
        let n = 0
        const original = ctrl.restickify.bind(ctrl)
        ctrl.restickify = (...a) => { n += 1; return original(...a) }
        window.dispatchEvent(new CustomEvent("blade-stack:relayout"))
        return n
      })()
    JS
    assert_equal 1, gezaehlt
  end

  test "simple-tabs: initial schlaegt das Gedaechtnis, und jeder Wechsel meldet sich" do
    stapel_oeffnen
    page.execute_script(<<~JS)
      window.__reiter = []
      document.addEventListener("simple-tabs:gewechselt", (e) => window.__reiter.push(e.detail.name))
      sessionStorage.setItem("simple-tabs:probe1674", "a")
      const wrap = document.createElement("div")
      wrap.id = "reiter_probe"
      wrap.style.cssText = "position:fixed;top:0;left:0;z-index:9999;background:white"
      wrap.dataset.controller = "simple-tabs"
      wrap.dataset.simpleTabsInitialValue = "b"
      wrap.dataset.simpleTabsStorageKeyValue = "probe1674"
      wrap.innerHTML = `
        <button type="button" id="reiter_a" data-simple-tabs-target="tab" data-name="a" data-action="simple-tabs#show">A</button>
        <button type="button" id="reiter_b" data-simple-tabs-target="tab" data-name="b" data-action="simple-tabs#show">B</button>
        <div data-simple-tabs-target="panel" data-name="a" id="feld_a">Feld A</div>
        <div data-simple-tabs-target="panel" data-name="b" id="feld_b">Feld B</div>`
      document.body.appendChild(wrap)
    JS

    assert_selector "#feld_b", visible: true, wait: 5
    assert_no_selector "#feld_a", visible: true
    assert_equal ["b"], page.evaluate_script("window.__reiter"), "auch das Aufgehen meldet sich"
    assert_equal "b", page.evaluate_script("sessionStorage.getItem('simple-tabs:probe1674')"),
                 "der Wunsch-Reiter wird gleich gemerkt, sonst spränge die Card beim nächsten Re-Render zurück"

    find("#reiter_a").click
    assert_selector "#feld_a", visible: true, wait: 5
    assert_equal %w[b a], page.evaluate_script("window.__reiter")
  end
end
