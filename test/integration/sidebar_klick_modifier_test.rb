require "test_helper"

# #1509 (Hans): „Außerdem haben sich mit den Tastatur-Modifiern eigentlich die
# Plus-Zeichen in den Listen erledigt … Deshalb die Plus-Zeichen bitte überall
# entfernen." — Nachtrag: „Dann die Modifier für den Mausklick auf die Sidebar
# übertragen."
#
# Diese Datei prüft, was im Markup der Seitenleiste steht. Was ein Klick
# daraus macht, prüft test/system/blade_stack_test.rb — dafür braucht es einen
# Browser.
class SidebarKlickModifierTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "sb-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    %w[Task Topic KnowledgeItem Awaiting Communication Source Document Actor].each do |res|
      grant(@hans, res, %w[read create update])
    end
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  # Damit die Sonderfall-Zeile „zuletzt geöffnet" im Markup landet: Sie
  # speist sich aus ActorView, das sonst der View-Tracker im Browser füllt
  # (ab 3s Verweildauer) — im Integrationstest also von Hand.
  def thema_mit_verlauf
    thema = Topic.create!(name: "Sidebar-Modifier-Thema",
                          slug: "sb-mod-#{SecureRandom.hex(2)}", creator: @hans)
    @hans.update_preferences("sidebar_recent_topics_count" => 5)
    ActorView.create!(actor: @hans, viewable: thema, duration_ms: 5_000,
                      viewed_at: Time.current)
    thema
  end

  test "die Plus-Zeichen sind aus der Seitenleiste verschwunden" do
    thema_mit_verlauf
    get "/dashboard"

    assert_response :success
    assert_not_includes @response.body, "sidebar-blade-plus",
                        "das Plus-Bauteil darf es nicht mehr geben"
    assert_not_includes @response.body, "Rechts daneben öffnen",
                        "auch seine Beschriftung nicht"
  end

  test "eine Sidebar-Zeile traegt den Card-Aufruf — aber nur mit Modifier" do
    get "/dashboard"

    assert_response :success
    zeile = @response.body[%r{<a[^>]*data-blade-link-id-value="tasks"[^>]*>}]
    assert zeile, "die Aufgaben-Zeile muss den Card-Aufruf tragen"
    assert_includes zeile, %(data-blade-link-kind-value="list")
    assert_includes zeile, %(data-blade-link-nur-modifier-value="true"),
                    "ohne Modifier navigiert die Zeile weiter, wie die Leiste es immer tat"
    assert_includes zeile, "click-&gt;blade-link#append",
                    "HTML-escaped — das Markup traegt die Aktion, nicht der Rohtext"
    assert_includes zeile, "click-&gt;sidebar#hoverCollapse",
                    "die gewachsenen Klick-Aktionen bleiben daneben stehen"
    assert_includes zeile, %(data-stack-reset-id="list:tasks"),
                    "#434: der Stack-Reset haengt weiter an derselben Zeile"
  end

  test "auch Verlaufs- und Wartend-Zeile tragen die Regel" do
    thema = thema_mit_verlauf
    get "/dashboard"

    assert_response :success
    treffer = @response.body.scan(%r{<a[^>]*data-blade-link-id-value="#{thema.slug}"[^>]*>})
    assert_operator treffer.size, :>=, 1, "die Verlaufs-Zeile muss den Card-Aufruf tragen"
    treffer.each do |a|
      assert_includes a, %(data-blade-link-kind-value="topic_list")
      assert_includes a, %(data-blade-link-nur-modifier-value="true")
    end

    wartend = @response.body[%r{<a[^>]*data-blade-link-id-value="awaitings"[^>]*>}]
    assert wartend, "die Wartend-Zeile muss den Card-Aufruf tragen"
    assert_includes wartend, %(data-blade-link-nur-modifier-value="true")
    assert_includes wartend, %(data-stack-reset-id="list:awaitings")
  end
end
