require "test_helper"

# #1027: „E-Mail schreiben" an E-Mail-Kontaktpunkten — Compose-Ziel folgt
# der Nutzer-Vorliebe: ohne verbundenes Google-Konto mailto:, mit Vorliebe
# "gmail" der Gmail-Compose-Link. Dazu das Popover „mit Betreff und Text".
class MailComposeTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-mc-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Topic",   %w[read])
    grant(@hans, "Contact", %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @person = FileProxy.create(actor: @hans, title: "Mail-Kontakt",
                               item_type: :person, content: "",
                               topics: [], contacts: [], tags: [])
    @person.contact_points.create!(kind: "email", value: "kontakt@example.org")
  end

  test "ohne Google-Konto rendert der Kontaktpunkt einen mailto-Link + Compose-Popover" do
    get "/knowledge_items/#{@person.uuid}/card"
    assert_response :success
    assert_includes @response.body, "mailto:kontakt%40example.org"
    assert_includes @response.body, "data-mail-compose-strategy-value=\"mailto\""
    assert_includes @response.body, "data-mail-compose-target=\"body\""
  end

  test "mit Vorliebe gmail rendert der Kontaktpunkt den Gmail-Compose-Link" do
    @hans.update_preferences("mail_compose" => "gmail")
    get "/knowledge_items/#{@person.uuid}/card"
    assert_response :success
    assert_includes @response.body, "https://mail.google.com/mail/?"
    assert_includes @response.body, "data-mail-compose-strategy-value=\"gmail\""
  end

  # #1036: E-Mail-Vorlagen (vorlage:email-KIs) erscheinen als Auswahl im
  # Popover — Platzhalter pro Empfänger gemergt, "Betreff:"-Zeile → Betreff.
  test "vorlage:email-KI erscheint als gemergte Option im Compose-Popover" do
    FileProxy.create(actor: @hans, title: "Willkommen", item_type: :note,
                     content: "Betreff: Hallo {{name}}\nGuten Tag {{name}}, Ihre Adresse ist {{email}}. {{offen}}",
                     tags: ["vorlage:email"])
    get "/knowledge_items/#{@person.uuid}/card"
    assert_response :success
    assert_includes @response.body, "data-mail-compose-target=\"template\""
    assert_includes @response.body, "data-subject=\"Hallo Mail-Kontakt\""
    assert_includes @response.body, "Guten Tag Mail-Kontakt, Ihre Adresse ist kontakt@example.org."
    assert_includes @response.body, "{{offen}}", "unaufgelöste Platzhalter bleiben literal"
  end

  test "ohne E-Mail-Vorlagen rendert das Popover keine Vorlagen-Auswahl" do
    get "/knowledge_items/#{@person.uuid}/card"
    assert_response :success
    assert_not_includes @response.body, "data-mail-compose-target=\"template\""
  end
end
