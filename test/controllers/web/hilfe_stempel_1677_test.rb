require "test_helper"

# #1677 (Entsprechung zu immoOS #1658 R9/R12/R15): Ein Marker `:feld:<schlüssel>:`
# findet sein Ziel am sichersten über `data-i18n-key` — der sichtbare Text kann
# doppelt vorkommen oder nur als Platzhalter dastehen. Upstream tragen ihn die
# Stellen, an denen der Text-Rückfall des Zeigers nicht reicht: die Suchfelder
# der Listen (Beschriftung nur als Platzhalter) und die Reiter der Personen-Card.
class HilfeStempel1677Test < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[KnowledgeItem Communication Task Topic].each { |rt| grant(@hans, rt, %w[read create update]) }
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "das Suchfeld einer Liste traegt den Schluessel seines Platzhalters" do
    get "/tasks/list_card"
    assert_response :success
    assert_includes @response.body, %(data-i18n-key="tasks.list_search_placeholder")
    assert_includes @response.body, %(placeholder="#{I18n.t("tasks.list_search_placeholder")}")
  end

  test "ohne eigenen Schluessel traegt das Suchfeld den des Standard-Platzhalters" do
    html = ApplicationController.render(partial: "shared/list_search")
    assert_includes html, %(data-i18n-key="shared.list_search.placeholder")
  end

  test "ein frei getexteter Platzhalter bekommt KEINEN Schluessel" do
    html = ApplicationController.render(partial: "shared/list_search", locals: { placeholder: "Irgendwas filtern …" })
    assert_not_includes html, "data-i18n-key"
  end

  test "die Reiter der Personen-Card tragen ihren Schluessel" do
    person = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Erika Muster", item_type: :person,
                                   creator_id: @hans.id, file_path: "kb/#{SecureRandom.hex(4)}.md",
                                   content_hash: SecureRandom.hex(8))
    mail = Communication.create!(direction: "inbound", subject: "Angebots-Mail",
                                 external_id: "stempel-#{SecureRandom.hex(4)}")
    CommunicationMention.create!(communication: mail, mentioned: person, role: CommunicationMention::ROLES.first)

    get "/knowledge_items/#{person.uuid}/card"
    assert_response :success
    assert_includes @response.body, %(data-i18n-key="knowledge.person_tabs.master_data")
    assert_includes @response.body, %(data-i18n-key="knowledge.person_tabs.communication")
  end
end
