require "test_helper"

# #641: Quick-Add-Aufgabe in der Topbar — vier Tier-Presets
# (Topic+Zugewiesen) + Vorlagenliste unter den Feldern.
class QuickCreateBarTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[Task Topic Actor KnowledgeItem].each { |rt| grant(@hans, rt, %w[read create update]) }
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "Topbar-Quick-Add zeigt die vier Preset-Icons" do
    get "/tasks"
    assert_response :success
    %w[cat squirrel bird fish].each do |p|
      assert_includes @response.body, %(data-preset="#{p}"), "Preset #{p} fehlt"
    end
    assert_includes @response.body, "task-quickadd-prefs#selectPreset"
  end

  # #1644 (Hans): „Ich hätte gern oben zwei Optionsfelder: Person |
  # Organisation … Dann abhängig von der Option: Vorname/Nachname, Geschlecht
  # oder Organisationsname, Rechtsform."
  test "#1644 Der Personen-Slot bietet beide Arten mit ihren Feldern" do
    get "/tasks"
    assert_response :success

    assert_includes @response.body, %(data-controller="entity-type-switch")
    %w[person organization].each do |typ|
      assert_includes @response.body, %(data-entity-type-switch-typ-param="#{typ}"), "Option #{typ} fehlt"
      assert_includes @response.body, %(data-typ="#{typ}")
    end
    # Person: Vor-/Nachname + Geschlecht. Organisation: Name + Rechtsform.
    assert_includes @response.body, 'name="first_name"'
    assert_includes @response.body, 'name="last_name"'
    assert_includes @response.body, 'name="gender"'
    assert_includes @response.body, 'name="legal_form"'
    assert_includes @response.body, I18n.t("knowledge.legal_forms.gmbh")
  end

  test "#1644 Person entsteht aus Vor- und Nachname, ohne Titel" do
    with_isolated_miolimos_base do
      post "/knowledge_items",
           params: { quick_create: "1", item_type: "person",
                     first_name: "Erika", last_name: "Neu", gender: "female" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      p = KnowledgeItem.find_by(title: "Erika Neu")
      assert_not_nil p, "der Titel wird aus den Namensfeldern gebildet"
      assert_equal "person", p.item_type
      assert_equal ["Erika", "Neu", "female"], [p.first_name, p.last_name, p.gender]
    end
  end

  test "#1644 Organisation entsteht mit Name und Rechtsform" do
    with_isolated_miolimos_base do
      post "/knowledge_items",
           params: { quick_create: "1", item_type: "organization",
                     title: "Beispiel Bau", legal_form: "gmbh" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success

      org = KnowledgeItem.find_by(title: "Beispiel Bau")
      assert_not_nil org
      assert_equal "organization", org.item_type
      assert_equal "gmbh", org.legal_form
    end
  end

  test "Vorlagenliste liegt im Fluss unter den Feldern (kein absolute-Overlay)" do
    get "/tasks"
    list = @response.body[/<ul data-task-template-picker-target="list"[^>]*class="([^"]*)"/, 1]
    refute_nil list
    refute_includes list, "absolute"
    assert_includes list, "mt-2"
  end
end
