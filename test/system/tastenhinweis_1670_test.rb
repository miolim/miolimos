require "application_system_test_case"

# #1670 (Übernahme aus immoOS #1667, Hans): „Wenn man STRG+ALT oder
# STRG+UMSCHALT gedrückt hält, soll in der Topbar angezeigt werden, was man mit
# den Pfeiltasten machen kann. … Zusätzlich soll bei STRG+UMSCHALT die Farbe des
# Spines der fokussierten Card lila werden, damit deren Bewegung durch den Stack
# deutlich wird."
#
# Die Modifier werden als Tastenereignis geschickt: Ein echtes „Taste gedrückt
# HALTEN" kennt der Treiber nicht, und der Hinweis hängt ohnehin an genau diesen
# Ereignissen (keydown/keyup), nicht an der Pfeiltaste danach.
class Tastenhinweis1670Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    %w[Task Topic KnowledgeItem].each { |res| grant(@hans, res, %w[read create update]) }
    login_as(@hans)
    @task = Task.create!(title: "Tastenhinweis #{SecureRandom.hex(2)}", creator: @hans,
                         assignee: @hans, status: :open)
  end

  def taste(typ, strg: false, alt: false, umschalt: false)
    page.execute_script(<<~JS)
      window.dispatchEvent(new KeyboardEvent("#{typ}", {
        key: "Control", ctrlKey: #{strg}, altKey: #{alt}, shiftKey: #{umschalt}, bubbles: true
      }))
    JS
  end

  def hinweis_sichtbar? = page.evaluate_script(
    "!document.querySelector('.topbar-tastenhinweis').classList.contains('hidden')"
  )

  def hinweis_text = page.evaluate_script(
    "document.querySelector('[data-tastenhinweis-target=\"text\"]').textContent"
  )

  def tastenmodus = page.evaluate_script("document.documentElement.dataset.tastenmodus || null")

  def spine_farbe = page.evaluate_script(<<~JS)
    (() => {
      const spine = document.querySelector('.stack-card[data-active="true"] .stack-spine');
      return spine ? getComputedStyle(spine).backgroundColor : null;
    })()
  JS

  # Der Spine blendet die Farbe über eine Übergangszeit ein. Wer sofort misst,
  # bekommt einen Zwischenwert — in immoOS kam beim ersten Lauf rgb(142,235,175)
  # heraus, also Grün auf halbem Weg nach Lila.
  def warte_auf_spine_farbe(farbe)
    Timeout.timeout(3) { sleep 0.05 until spine_farbe == farbe }
  rescue Timeout::Error
    # Nichts tun — die Zusicherung im Test meldet den tatsächlichen Wert.
  end

  test "#1670: STRG+ALT kuendigt den Fokuswechsel an, STRG+UMSCHALT das Verschieben" do
    visit "/tasks?stack=task:#{@task.id}"
    assert_selector ".stack-card[data-active='true'] .stack-spine", wait: 20

    assert_not hinweis_sichtbar?, "ohne gedrueckte Taste steht nichts da"

    taste("keydown", strg: true, alt: true)
    assert hinweis_sichtbar?
    assert_equal I18n.t("shared.topbar.tastenhinweis.fokus"), hinweis_text
    # Lila gehoert NUR zum Verschieben — sonst sagte die Farbe nichts.
    assert_nil tastenmodus

    taste("keydown", strg: true, umschalt: true)
    assert hinweis_sichtbar?
    assert_equal I18n.t("shared.topbar.tastenhinweis.verschieben"), hinweis_text
    assert_equal "verschieben", tastenmodus
    warte_auf_spine_farbe("rgb(167, 139, 250)")
    assert_equal "rgb(167, 139, 250)", spine_farbe, "violet-400 auf der fokussierten Card"

    taste("keyup")
    assert_not hinweis_sichtbar?, "beim Loslassen verschwindet der Hinweis"
    assert_nil tastenmodus
    warte_auf_spine_farbe("rgb(74, 222, 128)")
    assert_equal "rgb(74, 222, 128)", spine_farbe, "wieder emerald-400, die normale Fokusfarbe"
  end

  # STRG allein ist der Kopieren-Griff, STRG+ALT+UMSCHALT loest keine der beiden
  # Pfeil-Aktionen aus. Beide duerfen nichts versprechen.
  test "#1670: andere Kombinationen kuendigen nichts an" do
    visit "/tasks?stack=task:#{@task.id}"
    assert_selector ".stack-card[data-active='true'] .stack-spine", wait: 20

    taste("keydown", strg: true)
    assert_not hinweis_sichtbar?

    taste("keydown", strg: true, alt: true, umschalt: true)
    assert_not hinweis_sichtbar?

    taste("keydown", alt: true)
    assert_not hinweis_sichtbar?
  end

  # Wer mit gedrueckter Taste ins andere Fenster klickt, bekommt nie ein keyup —
  # ohne den blur-Zweig bliebe die Topbar ueberblendet stehen.
  test "#1670: der Hinweis verschwindet, wenn das Fenster den Fokus verliert" do
    visit "/tasks?stack=task:#{@task.id}"
    assert_selector ".stack-card[data-active='true'] .stack-spine", wait: 20

    taste("keydown", strg: true, umschalt: true)
    assert hinweis_sichtbar?

    page.execute_script("window.dispatchEvent(new Event('blur'))")
    assert_not hinweis_sichtbar?
    assert_nil tastenmodus
  end
end
