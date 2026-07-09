require "test_helper"

# #849 (aus immoos übernommen, dort aus #848): dünne Tab-Leiste am
# Person/Org-Detail über den leichten simple_tabs-Controller. Der
# Kommunikations-Tab zeigt ausschließlich E-Mails und erscheint nur, wenn
# welche da sind; ohne E-Mails bleibt der schlichte Stapel ohne Tab-Leiste.
class PersonDetailTabsTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ptabs-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    %w[KnowledgeItem Communication Task Topic].each do |rt|
      grant(@hans, rt, %w[read create update])
    end
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def create_person(title)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title,
                          item_type: :person, creator_id: @hans.id,
                          file_path: "kb/#{SecureRandom.hex(4)}.md",
                          content_hash: SecureRandom.hex(8))
  end

  test "Person mit E-Mail bekommt Tab-Leiste mit Kommunikations-Tab (#849)" do
    person = create_person("Erika Muster")
    comm = Communication.create!(direction: "inbound", subject: "Angebots-Mail",
                                 external_id: "ptabs-#{SecureRandom.hex(4)}")
    CommunicationMention.create!(communication: comm, mentioned: person,
                                 role: CommunicationMention::ROLES.first)

    get "/knowledge_items/#{person.uuid}/card"
    assert_response :success
    assert_includes @response.body, %(data-controller="simple-tabs")
    assert_includes @response.body, %(data-simple-tabs-target="panel" data-name="master_data")
    assert_includes @response.body, %(data-name="communication")
    # Die E-Mail hängt im Panel; der Tab zeigt die E-Mail-Only-Liste
    # (section_emails), NICHT das kombinierte Backlinks-Panel.
    assert_includes @response.body, "Angebots-Mail"
    assert_includes @response.body, I18n.t("knowledge.list.backlinks.section_emails")
  end

  test "Kommunikations-Tab erscheint nur bei E-Mails, nicht bei sonstigen Backlinks (#849)" do
    # Person mit offenem Wartepunkt, aber OHNE E-Mail → kein Kommunikations-Tab,
    # damit auch keine Tab-Leiste; der Wartepunkt bleibt als Backlinks-Section.
    person = create_person("Nur Wartepunkt")
    person.awaitings.create!(title: "Rückruf", creator: @hans, follow_up_at: Date.current + 3)

    get "/knowledge_items/#{person.uuid}/card"
    assert_response :success
    assert_not_includes @response.body, %(data-name="communication")
    assert_not_includes @response.body, %(data-controller="simple-tabs")
    assert_includes @response.body, "Rückruf"
  end

  test "Person ganz ohne verknüpfte Daten bleibt flach, ohne Tab-Leiste (#849)" do
    person = create_person("Nackte Person")

    get "/knowledge_items/#{person.uuid}/card"
    assert_response :success
    assert_not_includes @response.body, %(data-controller="simple-tabs")
  end
end
