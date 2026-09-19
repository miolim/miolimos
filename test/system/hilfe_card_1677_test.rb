require "application_system_test_case"

# #1677 (aus immoOS #1658/#1665 übernommen): die Hilfe-Card im Browser.
#
# Gemessen wird der ganze Weg, den ein Mensch geht: Fragezeichen im Rücken →
# Hilfe-Card rechts daneben → Stift → schreiben → Häkchen → der Text steht da,
# mit Symbolen statt Markern. Dazu die beiden Verhalten, die nur im Browser
# entstehen: Die offene Hilfe folgt dem Reiter, und ein Klick auf einen Marker
# zeigt auf die Stelle in der Nachbar-Card.
#
# Vier Stimulus-Controller sind NEU (help-link, hilfe-zeiger, icon-picker,
# dirty-mark) — der Test stellt auch sicher, dass sie wirklich geladen werden.
class HilfeCard1677Test < ApplicationSystemTestCase
  setup do
    @hans = create_human(name: "Hans Groth")
    %w[KnowledgeItem Communication Task HelpCard].each { |rt| grant(@hans, rt, %w[read create update delete]) }
    @anna = FileProxy.create(actor: @hans, title: "Anna Bergmann", item_type: :person, content: "")
    login_as(@hans)
    page.driver.resize_window(1600, 900)
  end

  # Eine Person bekommt ihre Reiterleiste erst mit einer E-Mail (#849).
  def mit_kommunikation
    mail = Communication.create!(direction: "inbound", subject: "Angebots-Mail",
                                 external_id: "hilfe-#{SecureRandom.hex(4)}")
    CommunicationMention.create!(communication: mail, mentioned: @anna,
                                 role: CommunicationMention::ROLES.first)
  end

  def hilfe_uuid
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('article.stack-card[data-uuid^="help:"]');
        return el ? el.dataset.uuid : null;
      })()
    JS
  end

  def reiter_klicken(name)
    find("article.stack-card[data-uuid='#{@anna.uuid}'] " \
         "button[data-simple-tabs-target='tab'][data-name='#{name}']").click
  end

  def markiert
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('.hilfe-gezeigt');
        return el ? (el.dataset.i18nKey || el.dataset.uiIcon || el.textContent.trim()) : null;
      })()
    JS
  end

  test "das Fragezeichen oeffnet die Hilfe, Stift und Haekchen speichern sie" do
    aufgabe = create_task(creator: @hans, title: "Musteraufgabe")
    visit "/tasks?stack=task:#{aufgabe.id}"
    assert_selector "article.stack-card[data-uuid='task:#{aufgabe.id}']", wait: 20

    find("article.stack-card[data-uuid='task:#{aufgabe.id}'] button.spine-hilfe-icon").click
    assert_selector "article.stack-card[data-uuid='help:task']", wait: 10
    assert_text I18n.t("hilfe.notiz_leer")

    within("article.stack-card[data-uuid='help:task']") do
      find("button[data-description-toggle-target='editBtn']", match: :first).click
      # ?cm6 ist im Test nicht abgeschaltet: CodeMirror liegt über dem Textfeld.
      find(".cm-content", match: :first).click
      page.driver.browser.keyboard.type("Schließen geht mit :ui:karte_schliessen: oben rechts.")
      find("button[data-description-toggle-target='saveBtn']", match: :first).trigger(:mousedown)

      assert_text "Schließen geht mit", wait: 10
      # Der Marker ist zum Symbol geworden und nennt, wohin er zeigt.
      assert_selector "svg[data-hilfe-art='ui'][data-hilfe-schluessel='karte_schliessen']"
    end

    assert_equal "Schließen geht mit :ui:karte_schliessen: oben rechts.",
                 HelpCard.find_by!(key: "task").user_body.to_s.strip
  end

  test "Klick auf einen Marker hebt das Bedienelement auf der Nachbar-Card hervor" do
    aufgabe = create_task(creator: @hans, title: "Musteraufgabe")
    HelpCard.create!(key: "task", program_body: "Zu geht die Card mit :ui:karte_schliessen: wieder.")

    visit "/tasks?stack=task:#{aufgabe.id},help:task"
    assert_selector "[data-hilfe-schluessel='karte_schliessen']", wait: 20
    assert_nil markiert, "vor dem Klick darf nichts hervorgehoben sein"

    find("[data-hilfe-schluessel='karte_schliessen']").click
    assert_equal "karte_schliessen", markiert
    hervorgehoben_in = page.evaluate_script(
      "document.querySelector('.hilfe-gezeigt').closest('article.stack-card').dataset.uuid"
    )
    assert_equal "task:#{aufgabe.id}", hervorgehoben_in, "gezeigt wird auf der Nachbar-Card, nicht in der Hilfe"
  end

  test "ein Marker findet das Suchfeld der Liste ueber dessen Schluessel" do
    HelpCard.create!(key: "list:tasks",
                     program_body: "Oben steht :feld:tasks.list_search_placeholder: für die Liste.")

    visit "/tasks?stack=list:tasks,help:list:tasks"
    assert_selector "[data-hilfe-schluessel='tasks.list_search_placeholder']", wait: 20

    find("[data-hilfe-schluessel='tasks.list_search_placeholder']").click
    assert_equal "tasks.list_search_placeholder", markiert
  end

  test "#1665: der Reiterwechsel tauscht die offene Hilfe aus — und zurueck" do
    mit_kommunikation
    HelpCard.create!(key: "ki.master_data",   program_body: "Erklärung zu den Stammdaten.")
    HelpCard.create!(key: "ki.communication", program_body: "Erklärung zur Kommunikation.")

    visit "/knowledge_items?stack=#{@anna.uuid},help:ki.master_data"
    assert_text "Erklärung zu den Stammdaten.", wait: 20
    assert_equal "help:ki.master_data", hilfe_uuid

    reiter_klicken("communication")
    assert_text "Erklärung zur Kommunikation.", wait: 10
    assert_no_text "Erklärung zu den Stammdaten."
    assert_equal "help:ki.communication", hilfe_uuid,
                 "die Hilfe-Card steht am selben Platz, zeigt aber den neuen Reiter"

    reiter_klicken("master_data")
    assert_text "Erklärung zu den Stammdaten.", wait: 10
    assert_equal "help:ki.master_data", hilfe_uuid
  end

  test "#1665: das Fragezeichen oeffnet die Hilfe zum OFFENEN Reiter" do
    mit_kommunikation
    visit "/knowledge_items?stack=#{@anna.uuid}"
    assert_selector "article.stack-card[data-uuid='#{@anna.uuid}']", wait: 20

    reiter_klicken("communication")
    find("article.stack-card[data-uuid='#{@anna.uuid}'] button.spine-hilfe-icon").click
    assert_selector "article.stack-card[data-uuid='help:ki.communication']", wait: 10
  end

  # Ohne offene Hilfe darf ein Reiterklick keine aufmachen — sonst stünde
  # plötzlich eine Card im Stapel, die niemand angefordert hat.
  test "#1665: ohne offene Hilfe oeffnet der Reiterwechsel keine" do
    mit_kommunikation
    visit "/knowledge_items?stack=#{@anna.uuid}"
    assert_selector "article.stack-card[data-uuid='#{@anna.uuid}']", wait: 20

    reiter_klicken("communication")
    assert_no_selector "article.stack-card[data-uuid^='help:']", wait: 3
  end
end
