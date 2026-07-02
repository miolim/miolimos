require "application_system_test_case"

# #564: Sicherheitsnetz für die Listen-Blade-Flows — exakt die Bug-Klassen
# der Aufgaben #549/#557/#558/#563:
#   - Eintrag-Klick in einer Liste öffnet das Detail-Blade im selben Stack
#   - Plus am Eintrag appendet (statt neuen Stack zu öffnen)
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

  test "Personenliste: Plus appendet das Detail-Blade" do
    visit "/knowledge_items?stack=list:persons"
    assert page.has_css?("article.stack-card[data-uuid='list:persons']")
    # Der Plus-Button ist erst bei group-hover sichtbar — headless ist der
    # CSS-Hover unzuverlässig, darum JS-Klick (Testziel ist der Append).
    page.execute_script(<<~JS)
      document.querySelector("button[data-action*='appendFromList'][data-target-uuid='#{@person.uuid}']").click()
    JS
    assert page.has_css?("article.stack-card[data-uuid='#{@person.uuid}']"),
           "Plus muss das Detail-Blade appenden"
  end

  test "#563: KI-Liste öffnet Einträge auch auf /tasks (Seite ohne card-url-template)" do
    visit "/tasks"
    assert page.has_css?("[data-controller~='blade-stack']")
    # Personen-Liste per Sidebar-Plus an den Task-Stack appenden …
    find("button[data-blade-link-kind-value='list'][data-blade-link-id-value='persons']",
         visible: :all).click
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
