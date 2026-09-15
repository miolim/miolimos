require "application_system_test_case"

# #1617 (Hans): „Im Cardspine gibt es oben das Icon, um den Link oder den
# Wikilink zu kopieren. … Es wird grundsätzlich immer der Link kopiert. Mit
# UMSCHALT+Mausklick wird der Wikilink kopiert, falls vorhanden."
#
# Die echte Zwischenablage braucht im Headless-Browser eine Berechtigung —
# navigator.clipboard.writeText wird deshalb abgefangen und das Kopierte
# gemerkt. Geprüft wird, WAS kopiert wird und welcher Toast erscheint.
class BladeCopy1617Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    %w[Task Topic].each { |res| grant(@hans, res, %w[read create update]) }
    login_as(@hans)
  end

  def zwischenablage_abfangen!
    page.execute_script(<<~JS)
      window.__kopiert = []
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: (text) => { window.__kopiert.push(text); return Promise.resolve() } }
      })
    JS
  end

  # Im vollen Stack überdeckt eine Nachbar-Card den Spine teilweise — der
  # Klick wird deshalb direkt am Knopf ausgelöst, mit oder ohne Umschalt.
  def kopieren!(card, umschalt: false)
    page.execute_script(<<~JS)
      document.querySelector(#{"#{card} [data-controller~='copy-clipboard']".to_json})
        .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, shiftKey: #{umschalt} }))
    JS
  end

  def zuletzt_kopiert
    page.evaluate_script("window.__kopiert[window.__kopiert.length - 1]")
  end

  test "Aufgabe: Klick kopiert den Link, Umschalt+Klick den Wikilink" do
    task = Task.create!(title: "Kopier-Aufgabe", creator: @hans, assignee: @hans, status: :open)
    visit "/tasks?stack=list:tasks,task:#{task.id}"
    card = "article.stack-card[data-uuid='task:#{task.id}']"
    assert_selector card, wait: 10
    zwischenablage_abfangen!

    kopieren!(card)
    assert_equal "#{page.server_url}/tasks?stack=task:#{task.id}", zuletzt_kopiert
    assert_selector "#toast_stack", text: "Link kopiert"

    kopieren!(card, umschalt: true)
    assert_equal "[[##{task.id}]]", zuletzt_kopiert
    assert_selector "#toast_stack", text: "Wikilink kopiert: [[##{task.id}]]"
  end

  test "Thema ohne Wikilink: auch Umschalt+Klick kopiert den Link" do
    topic = Topic.create!(name: "Kopier-Thema", slug: "kopier-#{SecureRandom.hex(3)}", creator: @hans)
    visit "/topics/#{topic.slug}"
    btn = "[data-controller~='copy-clipboard'][data-copy-clipboard-content-value$='/topics/#{topic.slug}']"
    assert_selector btn, visible: :all, wait: 10
    zwischenablage_abfangen!

    page.execute_script(<<~JS)
      document.querySelector(#{btn.to_json})
        .dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, shiftKey: true }))
    JS
    assert_equal "#{page.server_url}/topics/#{topic.slug}", zuletzt_kopiert
  end
end
