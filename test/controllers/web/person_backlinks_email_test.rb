require "test_helper"

# #810: E-Mail-Links im Personen-Backlinks-Panel appenden die Communication
# als Blade an den AKTUELLEN Stack (openCommunication) statt zur
# Kommunikations-Seite zu navigieren.
class PersonBacklinksEmailTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-pbe-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Communication", %w[read])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "Task", %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "email backlink on a person card opens in the current stack" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Erika Muster",
                                item_type: :person, content: "x")
      comm = Communication.create!(direction: "inbound", subject: "Angebots-Mail",
                                   external_id: "pbe-#{SecureRandom.hex(4)}")
      CommunicationMention.create!(communication: comm, mentioned: person,
                                   role: CommunicationMention::ROLES.first)

      get "/knowledge_items/#{person.uuid}"
      assert_response :ok
      assert_includes @response.body, "Angebots-Mail"
      assert_includes @response.body, "blade-stack#openCommunication"
      assert_includes @response.body, %(data-communication-id="#{comm.id}")
    end
  end
end
