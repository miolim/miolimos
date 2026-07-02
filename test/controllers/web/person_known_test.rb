require "test_helper"

# #608: Personen-Bekanntheit — blaues Icon automatisch bei vorhandener
# Kommunikation, grünes bei manueller „persönlich bekannt"-Markierung
# (übersteuert Blau).
class PersonKnownTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[KnowledgeItem Communication Contact Topic].each { |rt| grant(@hans, rt, %w[read create update delete]) }
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @bekannt  = person!("Anna Auto")     # bekommt Kommunikation → blau
    @manuell  = person!("Max Manuell")   # wird manuell grün
    @fremd    = person!("Frieda Fremd")  # gar nichts

    mail = Email.create!(external_id: "pk-#{SecureRandom.hex(4)}", direction: :inbound,
                         subject: "Hallo", sent_at: Time.current)
    CommunicationMention.create!(communication: mail, mentioned_uuid: @bekannt.uuid, role: "sender")
  end

  def person!(title)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title, item_type: :person,
                          file_path: "x/#{title.parameterize}.md", content_hash: "h",
                          body: "", creator: @hans, published_at: Time.current)
  end

  test "personen-liste zeigt blau bei Kommunikation, grün bei manueller Markierung" do
    @manuell.update!(personally_known: true)
    get "/persons/list_card"
    assert_response :success
    assert_includes response.body, "Kommunikation mit dieser Person vorhanden" # blau (Anna)
    assert_includes response.body, "Persönlich bekannt (manuell gesetzt)"      # grün (Max)
  end

  test "grün übersteuert blau" do
    @bekannt.update!(personally_known: true)
    get "/persons/list_card"
    body = response.body
    # Anna hat Kommunikation UND manuelle Markierung → nur grün.
    assert_includes body, "Persönlich bekannt (manuell gesetzt)"
    refute_includes body, "Kommunikation mit dieser Person vorhanden"
  end

  test "toggle setzt und entfernt die manuelle Markierung" do
    post "/knowledge_items/#{@manuell.uuid}/toggle_personally_known"
    assert_response :success
    assert @manuell.reload.personally_known?

    post "/knowledge_items/#{@manuell.uuid}/toggle_personally_known"
    refute @manuell.reload.personally_known?
  end
end
