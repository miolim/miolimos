require "test_helper"

# #608/#840: Personen-Status. Seit #840 kodiert das Haupt-Icon den Status
# in Form+Farbe (blau = Kommunikation vorhanden, grün = manuell „persönlich
# bekannt", grün übersteuert blau); der Umschalter lebt im Klick-Menü am
# Icon (kein separater Button/kein separates Badge mehr).
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

  test "personen-liste kodiert Status im Haupticon: blau bei Kommunikation, grün bei manueller Markierung" do
    @manuell.update!(personally_known: true)
    get "/persons/list_card"
    assert_response :success
    # Titel-Attribute sind eindeutig dem Status-Icon zugeordnet.
    assert_includes response.body, 'title="Kommunikation vorhanden"' # blau (Anna)
    assert_includes response.body, 'title="Persönlich bekannt"'      # grün (Max)
    assert_includes response.body, "text-sky-600"                    # blaue Farbe
  end

  test "grün übersteuert blau" do
    @bekannt.update!(personally_known: true)
    get "/persons/list_card"
    body = response.body
    # Anna hat Kommunikation UND manuelle Markierung → nur grün, kein blaues Icon.
    assert_includes body, 'title="Persönlich bekannt"'
    refute_includes body, 'title="Kommunikation vorhanden"'
  end

  test "personen-card zeigt das Icon-Menü mit Umschalter statt separatem Button" do
    get "/knowledge_items/#{@fremd.uuid}/card"
    assert_response :success
    assert_includes response.body, "person_icon_menu_#{@fremd.uuid}"
    assert_includes response.body, I18n.t("knowledge.person_status.mark")
    # der alte separate Toggle ist weg
    refute_includes response.body, "person_known_toggle_#{@fremd.uuid}"
  end

  test "toggle setzt/entfernt die Markierung und liefert das aktualisierte Icon-Menü" do
    post "/knowledge_items/#{@manuell.uuid}/toggle_personally_known"
    assert_response :success
    assert @manuell.reload.personally_known?
    # Antwort ersetzt den Menü-Wrapper und zeigt den Grün-Zustand.
    assert_includes response.body, "person_icon_menu_#{@manuell.uuid}"
    assert_includes response.body, "text-emerald-600"
    assert_includes response.body, I18n.t("knowledge.person_status.unmark")

    post "/knowledge_items/#{@manuell.uuid}/toggle_personally_known"
    refute @manuell.reload.personally_known?
  end
end
