require "application_system_test_case"

# #564 Folge (Hans): Editor-System-Tests für die Textarea-Autocompletes —
# DAS Sicherheitsnetz vor der Konsolidierung von wikilink_autocomplete +
# cite_autocomplete (meistgenutzter Tipp-Pfad, vorher null Abdeckung).
# Getestet wird am KI-Edit (/knowledge_items/:uuid/edit), wo beide
# Controller an derselben Textarea hängen.
#
# #801: KI-Edit rendert inzwischen standardmäßig CM6 (versteckt die
# Textarea → ElementNotFound). Wir besuchen mit ?cm6=0 — das testet
# weiterhin den echten Textarea-Pfad, der auf Task-Beschreibung,
# Reply-Composer und Kommentaren ausgeliefert wird. Das CM6-eigene
# Autocomplete ist davon getrennt (cm6_editor_controller).
class EditorAutocompleteTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Source", %w[read])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "Task", %w[read])

    @alpha = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Alphanotiz",
                                   item_type: "note", creator: @hans,
                                   file_path: "x/alpha.md", content_hash: "h", body: "A")
    @beta  = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Betanotiz",
                                   item_type: "note", creator: @hans,
                                   file_path: "x/beta.md", content_hash: "h", body: "B")
    @edited = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Editor-Probe",
                                    item_type: "note", creator: @hans,
                                    file_path: "x/probe.md", content_hash: "h", body: "")
    @source = Source.create!(slug: "mustermann_2026", title: "Musterwerk",
                             csl_type: "book", creator: @hans)
    login_as(@hans)
  end

  # Auf der Edit-Seite hängen ZWEI Autocomplete-Textareas (Body-Editor +
  # Reply-Composer) — wir testen am Body-Editor (name=content) und scopen
  # die Listen relativ zu dessen Wrapper.
  def textarea
    find("textarea[name='content'][data-wikilink-autocomplete-target='input']")
  end

  def wrapper       = textarea.ancestor("[data-controller~='wikilink-autocomplete']")
  def wikilink_list = wrapper.find("ul[data-wikilink-autocomplete-target='list']", visible: :all)
  def cite_list     = wrapper.find("ul[data-cite-autocomplete-target='list']", visible: :all)

  def caret_position
    page.evaluate_script("document.querySelector(\"textarea[name='content']\").selectionStart")
  end

  test "Wikilink: [[ öffnet Vorschläge, tippen filtert, Enter fügt [[Titel]] ein" do
    visit "/knowledge_items/#{@edited.uuid}/edit?cm6=0"
    textarea.click
    textarea.send_keys("Siehe [[Alpha")

    assert wikilink_list.has_css?("li", text: "Alphanotiz", wait: 5),
           "Vorschlagsliste muss Alphanotiz zeigen"
    refute wikilink_list.has_css?("li", text: "Betanotiz"),
           "gefilterte Liste darf Betanotiz nicht zeigen"

    textarea.send_keys(:enter)
    assert_equal "Siehe [[Alphanotiz]]", textarea.value
    # Cursor steht NACH dem schließenden ]] (weitertippen im Fließtext).
    assert_equal "Siehe [[Alphanotiz]]".length, caret_position
    assert wikilink_list.matches_css?(".hidden"), "Liste muss nach Auswahl zu sein"
  end

  test "Wikilink: Escape schließt ohne Einfügen" do
    visit "/knowledge_items/#{@edited.uuid}/edit?cm6=0"
    textarea.click
    textarea.send_keys("[[Beta")
    assert wikilink_list.has_css?("li", text: "Betanotiz", wait: 5)

    textarea.send_keys(:escape)
    assert wikilink_list.matches_css?(".hidden"), "Escape muss die Liste schließen"
    assert_equal "[[Beta", textarea.value, "Escape darf nichts einfügen"
  end

  test "Wikilink: Pfeiltasten navigieren, Auswahl folgt" do
    visit "/knowledge_items/#{@edited.uuid}/edit?cm6=0"
    textarea.click
    textarea.send_keys("[[notiz")   # matcht Alpha + Beta
    assert wikilink_list.has_css?("li", count: 2, wait: 5)

    # Das offene Dropdown überlappt die Textarea — Cuprite-send_keys läuft
    # über einen Klick und träfe das <li>. Keydown direkt dispatchen (der
    # Controller hört auf keydown an der Textarea).
    press = ->(key) {
      page.execute_script(<<~JS)
        document.querySelector("textarea[name='content']").dispatchEvent(
          new KeyboardEvent("keydown", { key: "#{key}", bubbles: true, cancelable: true }))
      JS
    }
    press.call("ArrowDown")
    # zweiter Eintrag aktiv (bg-emerald-50)
    actives = wikilink_list.all("li.bg-emerald-50").map(&:text)
    assert_equal 1, actives.size
    press.call("Enter")
    assert_match(/\A\[\[(Alphanotiz|Betanotiz)\]\]\z/, textarea.value)
  end

  test "Cite: [@ öffnet Quellen, Enter fügt [@slug] mit Cursor vor ] ein" do
    visit "/knowledge_items/#{@edited.uuid}/edit?cm6=0"
    textarea.click
    textarea.send_keys("Beleg [@muster")

    assert cite_list.has_css?("li", text: "mustermann_2026", wait: 5),
           "Quellen-Liste muss den Slug zeigen"
    textarea.send_keys(:enter)
    assert_equal "Beleg [@mustermann_2026]", textarea.value
    # Cursor VOR dem ], damit man direkt ", S. 33" weitertippen kann.
    assert_equal "Beleg [@mustermann_2026".length, caret_position
  end

  test "Cite: Komma in der Query (Locator) schließt die Liste" do
    visit "/knowledge_items/#{@edited.uuid}/edit?cm6=0"
    textarea.click
    textarea.send_keys("Beleg [@muster")
    assert cite_list.has_css?("li", wait: 5)
    textarea.send_keys(", S. 33")
    assert cite_list.matches_css?(".hidden"), "Locator-Komma muss die Liste schließen"
  end
end
