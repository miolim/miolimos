require "application_system_test_case"

# #1572 (Hans, 2026-09-12): Das Antwort-Feld klebt am unteren Rand der
# Card und schrumpft beim Hochscrollen bis auf zwei Zeilen, damit man
# beim Eingehen auf einzelne Punkte einer langen Antwort nicht mehr
# hoch- und runterscrollen muss.
#
# Die Rechnung selbst liegt in app/javascript/lib/sticky_compose.js und
# ist mit `node --test test/javascript/` abgedeckt. Hier wird die
# Verdrahtung im echten Layout geprueft: klebt es, schrumpft es, kommt
# es beim Zurueckscrollen wieder auf volle Hoehe.
#
# ACHTUNG: System-Tests laden JS aus public/assets (Propshaft-Static-
# Resolver) — vor dem Lauf `RAILS_ENV=production bin/rails assets:precompile`,
# sonst laeuft der Test gegen das JS des letzten Deploys.
class StickyComposeTest < ApplicationSystemTestCase
  # Ermittelt Geometrie von Form, Editor und Card-Scroll-Container.
  MESSEN = <<~JS.freeze
    (() => {
      const form = document.querySelector("form[data-controller~='sticky-compose']")
      if (!form) return null
      const editor = form.querySelector(".cm-editor")
      let view = form.parentElement
      while (view) {
        const o = getComputedStyle(view).overflowY
        if (o === "auto" || o === "scroll") break
        view = view.parentElement
      }
      if (!view) return null
      const f = form.getBoundingClientRect()
      const v = view.getBoundingClientRect()
      return {
        editorHeight: editor ? editor.getBoundingClientRect().height : 0,
        formBottom: f.bottom, formTop: f.top,
        viewBottom: v.bottom, viewTop: v.top,
        maxScroll: view.scrollHeight - view.clientHeight
      }
    })()
  JS

  SCROLLEN = <<~JS.freeze
    const form = document.querySelector("form[data-controller~='sticky-compose']")
    let view = form.parentElement
    while (view) {
      const o = getComputedStyle(view).overflowY
      if (o === "auto" || o === "scroll") break
      view = view.parentElement
    }
    const ziel = arguments[0]
    view.scrollTop = ziel < 0 ? view.scrollHeight : ziel
  JS

  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update])
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Topic", %w[read])
    @task = Task.create!(title: "Sticky-Compose Test-Task", creator: @hans, assignee: @hans)
    # Zwei lange Antworten — die letzten beiden rendert die Liste
    # aufgeklappt, damit der Antworten-Bereich hoch genug zum Scrollen
    # ist. Die Klebe-Strecke ist genau dieser Bereich.
    2.times do |i|
      KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Sticky-Reply-#{i}",
                            item_type: :reply, creator: @hans,
                            file_path: "x/sticky#{i}.md", content_hash: "h#{i}",
                            body: (["Eine Zeile Antworttext, lang genug zum Scrollen."] * 40).join("\n\n"),
                            parent_type: "Task", parent_id_int: @task.id,
                            published_at: Time.current)
    end
    login_as(@hans)
    visit "/tasks/#{@task.id}"
    find("form[data-controller~='sticky-compose'] .cm-content", wait: 10)
  end

  def mess
    sleep 0.3   # zwei Frames: der Controller rechnet im requestAnimationFrame
    page.evaluate_script(MESSEN)
  end

  def scrolle(ziel)
    page.execute_script(SCROLLEN, ziel)
  end

  test "leeres Feld bleibt beim Hochscrollen am unteren Card-Rand sichtbar" do
    scrolle(-1)   # ganz nach unten
    unten = mess
    refute_nil unten, "Form und Card-Scroll-Container muessen auffindbar sein"
    assert unten["maxScroll"] > 300,
      "Testaufbau: die Card muss scrollbar sein (maxScroll=#{unten['maxScroll']})"

    # 300px hoch — mitten in die Antwortenliste, also innerhalb der
    # Klebe-Strecke.
    scrolle(unten["maxScroll"] - 300)
    oben = mess

    assert oben["formBottom"] <= oben["viewBottom"] + 1,
      "Feld darf nicht unter die Card-Kante rutschen (#{oben['formBottom']} > #{oben['viewBottom']})"
    assert oben["formBottom"] > oben["viewBottom"] - 40,
      "Feld muss am unteren Rand kleben, nicht mitgescrollt sein " \
      "(formBottom=#{oben['formBottom']}, viewBottom=#{oben['viewBottom']})"
    assert oben["formTop"] < oben["viewBottom"],
      "Feld muss im sichtbaren Bereich liegen"
  end

  test "Entwurf schrumpft beim Hochscrollen bis auf zwei Zeilen und waechst wieder" do
    scrolle(-1)
    within("form[data-controller~='sticky-compose']") do
      find(".cm-content").send_keys((1..12).map { |i| "Zeile #{i} des Entwurfs" }.join("\n"))
    end
    scrolle(-1)
    voll = mess
    assert voll["editorHeight"] > 150,
      "Testaufbau: der Entwurf muss das Feld deutlich wachsen lassen (#{voll['editorHeight']}px)"

    # Das Feld gibt genau so viel Hoehe ab, wie herausgerutscht ist.
    # Gemessen wird als Differenz zweier Scroll-Stellungen: der Abstand
    # zwischen Feld-Unterkante und Scroll-Ende ist kein runder Wert
    # (unter dem Antworten-Bereich liegt noch die Aktivitaets-Sektion),
    # die Kopplung 1:1 dagegen schon.
    scrolle(voll["maxScroll"] - 100)
    etwas = mess
    assert etwas["editorHeight"] < voll["editorHeight"] - 30,
      "Feld muss beim Hochscrollen ueberhaupt schrumpfen " \
      "(voll=#{voll['editorHeight']}, jetzt=#{etwas['editorHeight']})"

    scrolle(voll["maxScroll"] - 150)
    weiter = mess
    assert_in_delta 50, etwas["editorHeight"] - weiter["editorHeight"], 8,
      "50px weiter hoch = 50px weniger Feldhoehe " \
      "(#{etwas['editorHeight']} -> #{weiter['editorHeight']})"

    # Weit hoch: Untergrenze zwei Zeilen (~62px inkl. Padding/Border).
    scrolle(weiter["maxScroll"] - 600)
    klein = mess
    assert klein["editorHeight"] < 90,
      "Feld muss auf die Minimalgroesse zusammengehen (#{klein['editorHeight']}px)"
    assert klein["editorHeight"] > 40,
      "Feld darf nicht unter zwei Zeilen fallen (#{klein['editorHeight']}px)"
    assert klein["formBottom"] <= klein["viewBottom"] + 1,
      "Feld klebt auch in Minimalgroesse am unteren Rand"

    # Zurueck an den Boden: wieder volle Hoehe, nichts bleibt geschrumpft.
    scrolle(-1)
    zurueck = mess
    assert_in_delta voll["editorHeight"], zurueck["editorHeight"], 4,
      "Feld muss unten wieder voll ausgefahren sein " \
      "(vorher=#{voll['editorHeight']}, jetzt=#{zurueck['editorHeight']})"
  end
end
