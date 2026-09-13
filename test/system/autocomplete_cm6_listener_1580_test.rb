require "application_system_test_case"

# #1580 (aus immoOS #1578): „Missing target element "list" for
# "wikilink-autocomplete"" bei jedem Klick auf die Seite.
#
# Ursache: cm6-editor nimmt die Tokens wikilink-/cite-autocomplete aus
# data-controller (#373). Stimulus ruft daraufhin disconnect() — aber das
# Element passt dann nicht mehr zum Controller-Selektor, also findet
# `this.inputTarget` nichts und WIRFT, bevor der Dokument-Klick-Listener
# entfernt wird. Der Listener bleibt hängen, jeder spätere Klick ruft
# close() → `this.listTarget` → Fehler. Die Listen sind die ganze Zeit
# im Markup; nur die Zugehörigkeit zum Controller ist weg.
#
# Der Test reproduziert genau diesen Pfad (CM6 aktiv, nichts künstlich
# entfernt) und verlangt, dass ein Klick außerhalb keinen Fehler wirft.
class AutocompleteCm6Listener1580Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Source", %w[read])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "Task", %w[read])
    @item = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "CM6-Probe",
                                  item_type: "note", creator: @hans,
                                  file_path: "x/cm6-probe.md", content_hash: "h", body: "")
    login_as(@hans)
  end

  test "mit CM6 wirft ein Klick außerhalb des Editors keinen Autocomplete-Fehler" do
    visit "/knowledge_items/#{@item.uuid}/edit"
    assert_selector ".cm-editor", wait: 5

    # Vorbedingung: cm6-editor hat die Autocomplete-Tokens abgenommen, die
    # Listen stehen aber weiter im Markup.
    stand = page.evaluate_script(<<~JS)
      (() => ({
        tokens: document.querySelectorAll("[data-controller~='wikilink-autocomplete']").length,
        lists:  document.querySelectorAll("[data-wikilink-autocomplete-target='list']").length
      }))()
    JS
    assert_equal 0, stand["tokens"], "Vorbedingung: CM6 hat die Autocomplete-Controller abgelöst"
    assert_operator stand["lists"], :>, 0, "Vorbedingung: Listen stehen im Markup"

    page.execute_script(<<~JS)
      window.__fehler1580 = []
      window.addEventListener("error", (e) => window.__fehler1580.push(String(e.message)))
      document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    JS
    sleep 0.3

    assert_equal [], page.evaluate_script("window.__fehler1580")
  end
end
