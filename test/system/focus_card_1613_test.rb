require "application_system_test_case"

# #1613 (Hans): „Wenn ich Hauptfenster > Karte > Card-Werkzeugleiste >
# Fokusansicht — nur diese Karte klicke, wird zwar ein neues ‚Fenster'
# geöffnet, darin wird aber nichts angezeigt."
#
# Ursache (auf os.miolim.de mit Hans' Stack nachgemessen): Die fokussierte
# Card stand richtig im Bild, trug aber `clip-path: inset(0 913px 0 0)` —
# bei 736px Breite komplett weggeschnitten. Den Beschnitt setzt die
# Überstand-Regel aus #1228 bei jedem Scroll: „eine Card ist höchstens bis
# zur linken Kante ihrer Nachfolgerin sichtbar". Im Fokus ist die
# Nachfolgerin `display: none`, ihr Rect also 0/0 — der ganze Rest der Card
# galt als Überstand. Beim Fokussieren springt der Stack an den Anfang
# (scrollLeft 2442 → 0); dieser Scroll löste den Beschnitt aus.
class FocusCard1613Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    %w[Task Topic KnowledgeItem].each { |res| grant(@hans, res, %w[read create update]) }
    login_as(@hans)
  end

  def aufgabe(titel)
    Task.create!(title: "#{titel} #{SecureRandom.hex(2)}", description: "Beschreibung von #{titel}",
                 creator: @hans, assignee: @hans, status: :open)
  end

  test "Fokus auf eine Card mit Nachfolgerin: nach dem Scrollen bleibt sie sichtbar" do
    vorn   = Array.new(3) { |i| aufgabe("Vorn-#{i}") }
    ziel   = aufgabe("Ziel")
    hinten = Array.new(2) { |i| aufgabe("Hinten-#{i}") }
    ids = ["list:dashboard"] + (vorn + [ziel] + hinten).map { |t| "task:#{t.id}" }
    visit "/dashboard?stack=#{ids.join(',')}"

    card = "article.stack-card[data-uuid='task:#{ziel.id}']"
    assert_selector card, wait: 10
    sleep 0.5
    # Im vollen Stack überdeckt die nächste Card einen Teil der Ziel-Card —
    # Capybara verweigert dann den Klick. Der Controller hört am <body>, ein
    # Klick am Knopf selbst ist gleichwertig.
    page.execute_script("document.querySelector(#{"#{card} [data-focus-trigger='blade']".to_json}).click()")
    assert_selector "body.focus-blade", wait: 3
    # Wie bei Hans: der Stack scrollt im Fokus — das stößt den Beschnitt an.
    page.execute_script(<<~JS)
      document.getElementById("blade_stack_container").dispatchEvent(new Event("scroll"))
    JS
    sleep 0.5

    lage = page.evaluate_script(<<~JS)
      (() => {
        const c = document.querySelector(#{card.to_json})
        const r = c.getBoundingClientRect()
        return { clip: getComputedStyle(c).clipPath, breite: r.width,
                 treffer: !!document.elementFromPoint(r.left + r.width / 2, r.top + 80)?.closest(#{card.to_json}) }
      })()
    JS
    assert lage["breite"] > 300, "Die fokussierte Card braucht ihre Breite: #{lage.inspect}"
    assert_includes ["none", ""], lage["clip"], "Die fokussierte Card darf nicht beschnitten sein: #{lage.inspect}"
    assert lage["treffer"], "Die Mitte der fokussierten Card muss sichtbar sein: #{lage.inspect}"
    within(card) { assert_text ziel.title }
  end
end
