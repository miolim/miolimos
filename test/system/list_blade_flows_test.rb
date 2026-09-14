require "application_system_test_case"

# #564: Sicherheitsnetz für die Listen-Blade-Flows — exakt die Bug-Klassen
# der Aufgaben #549/#557/#558/#563:
#   - Eintrag-Klick in einer Liste öffnet das Detail-Blade im selben Stack
#   - Alt-Klick am Eintrag hängt an (statt neuen Stack zu öffnen; #1579: kein Plus mehr)
#   - Listen-Filter re-rendert in-place und wirft den Stack NICHT weg
#   - KI-Listen funktionieren auch auf Seiten OHNE card-url-template (#563)
class ListBladeFlowsTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    %w[KnowledgeItem Topic Task Document TimeEntry Contact].each { |rt| grant(@hans, rt, %w[read create update]) }

    @person = KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: "Ada Lovelace", item_type: "person",
      creator: @hans, file_path: "x/ada.md", content_hash: "h-ada"
    )
    login_as(@hans)
  end

  test "Personenliste: Eintrag-Klick öffnet Detail-Blade im selben Stack" do
    visit "/knowledge_items?stack=list:persons"
    assert page.has_css?("article.stack-card[data-uuid='list:persons']")

    click_on "Ada Lovelace"
    assert page.has_css?("article.stack-card[data-uuid='#{@person.uuid}']"),
           "Detail-Blade der Person muss im Stack erscheinen"
    # Liste bleibt als erstes Blade erhalten (kein Voll-Navigations-Reset).
    uuids = page.all("article.stack-card[data-uuid]").map { |el| el["data-uuid"] }
    assert_equal "list:persons", uuids.first
  end

  # #1604 (aus immoos #1579, Hans): „In der Personenliste gibt es noch ein
  # Plus-Zeichen bei Mouse-Over … Das bitte entfernen; es wird jetzt über den
  # Mouseklick-Modifier erreicht." Der Plus-Knopf ist fort; angehängt wird mit
  # ALT-Klick auf den Namen (#1509). Capybara nimmt den Modifier als
  # Positionsargument.
  test "Personenliste: Alt-Klick hängt das Detail-Blade an, ein Plus gibt es nicht mehr" do
    visit "/knowledge_items?stack=list:persons"
    assert page.has_css?("article.stack-card[data-uuid='list:persons']")
    assert_no_selector "button[data-action*='appendFromList'][data-target-uuid='#{@person.uuid}']", visible: :all

    find("article.stack-card[data-uuid='list:persons'] a", text: "Ada Lovelace").click(:alt)
    assert page.has_css?("article.stack-card[data-uuid='#{@person.uuid}']"),
           "Alt-Klick muss das Detail-Blade anhängen"
  end

  test "#563: KI-Liste öffnet Einträge auch auf /tasks (Seite ohne card-url-template)" do
    visit "/tasks"
    assert page.has_css?("[data-controller~='blade-stack']")
    # Personen-Liste aus der Seitenleiste an den Task-Stack anhaengen …
    # #1509: Bis hierher hing dafuer ein Plus-Button an der Zeile. Den gibt es
    # nicht mehr — die ZEILE traegt den Card-Aufruf, aber nur mit Modifier:
    # ohne gedrueckte Taste navigiert sie weiter zur Seite. ALT haengt an.
    # (Capybara nimmt Modifier als POSITIONSARGUMENT, nicht als `modifiers:` —
    # mit der falschen Form klickt es stillschweigend OHNE Modifier, und der
    # Test navigiert weg statt anzuhaengen.)
    find("a[data-blade-link-kind-value='list'][data-blade-link-id-value='persons']",
         visible: :all).click(:alt)
    assert page.has_css?("article.stack-card[data-uuid='list:persons']"),
           "Personen-Liste muss am Task-Stack hängen"
    # … und ein Eintrag-Klick muss das Detail öffnen (war #563: leere URL).
    click_on "Ada Lovelace"
    assert page.has_css?("article.stack-card[data-uuid='#{@person.uuid}']"),
           "Detail-Blade muss auch ohne data-card-url-template öffnen"
  end

  test "#558: Dokumentliste filtern lässt den Stack stehen" do
    doc = Document.create!(kind: :brief, subject: "Filter-Probe", status: :entwurf)
    visit "/documents?stack=list:documents,document:#{doc.id}"
    assert page.has_css?("article.stack-card[data-uuid='document:#{doc.id}']")

    # Filter abschicken (turbo-frame in-place) — Detail-Blade bleibt.
    within("article.stack-card[data-uuid='list:documents']") do
      select "Brief", from: "kind" rescue nil
      click_on "Filtern"
    end
    assert page.has_css?("article.stack-card[data-uuid='document:#{doc.id}']"),
           "Filtern darf das angehängte Detail-Blade nicht entfernen"
  end
end
