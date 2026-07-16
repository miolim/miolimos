require "test_helper"

# #1036 (Hans): Sichtbare Verwaltung der Dokument- & E-Mail-Vorlagen —
# Anlegen erzeugt eine Notiz-KI mit Tag "vorlage:<typ>", Entfernen nimmt
# nur den Tag weg (KI bleibt), das Blade listet nach Typ gruppiert.
class Settings::DocumentTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-dt-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret", role: :admin
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "create legt eine Notiz-KI mit vorlage-Tag an und öffnet sie im Stack" do
    post "/settings/document_templates", params: { kind: "email", title: "Mahnung freundlich" }
    ki = KnowledgeItem.find_by(title: "Mahnung freundlich")
    assert ki, "Vorlagen-KI wurde angelegt"
    assert_equal "note", ki.item_type
    assert_includes ki.tags, "vorlage:email"
    assert_redirected_to %r{stack=.*#{ki.uuid}}
  end

  test "create mit unbekanntem Typ legt nichts an" do
    post "/settings/document_templates", params: { kind: "quatsch", title: "Nope" }
    assert_nil KnowledgeItem.find_by(title: "Nope")
  end

  test "destroy entfernt nur den vorlage-Tag, die KI bleibt" do
    ki = FileProxy.create(actor: @hans, title: "NDA-Klauseln", item_type: :note,
                          content: "Text", tags: ["vorlage:nda", "recht"])
    delete "/settings/document_templates/#{ki.uuid}"
    ki.reload
    assert_not_includes ki.tags, "vorlage:nda"
    assert_includes ki.tags, "recht", "fremde Tags bleiben unangetastet"
    assert_nil ki.deleted_at, "KI selbst bleibt bestehen"
  end

  test "blade listet Vorlagen gruppiert und markiert die aktive" do
    older = FileProxy.create(actor: @hans, title: "Brief alt", item_type: :note,
                             content: "", tags: ["vorlage:brief"])
    KnowledgeItem.where(uuid: older.uuid).update_all(created_at: 2.days.ago)
    FileProxy.create(actor: @hans, title: "Brief neu", item_type: :note,
                     content: "", tags: ["vorlage:brief"])
    get "/settings/blade/document_templates"
    assert_response :success
    assert_includes @response.body, "Brief alt"
    assert_includes @response.body, "Brief neu"
    assert_match %r{>\s*aktiv\s*<}, @response.body, "älteste Vorlage ist als aktiv markiert"
    assert_match %r{>\s*inaktiv\s*<}, @response.body, "jüngere Vorlage ist als inaktiv markiert"
  end

  # #1036 Follow-up: Platzhalter-Chips im Edit-Modus — nur bei Vorlagen-KIs.
  test "edit einer Vorlagen-KI zeigt Platzhalter-Chips, normale Notiz nicht" do
    brief = FileProxy.create(actor: @hans, title: "Brief-Vorlage", item_type: :note,
                             content: "", tags: ["vorlage:brief"])
    get "/knowledge_items/#{brief.uuid}/edit"
    assert_response :success
    assert_includes @response.body, "data-copy-clipboard-content-value=\"{{empfaenger}}\""
    assert_includes @response.body, "data-copy-clipboard-content-value=\"{{anrede}}\""
    assert_includes @response.body, "Infoblock-Feld"

    email = FileProxy.create(actor: @hans, title: "Mail-Vorlage", item_type: :note,
                             content: "", tags: ["vorlage:email"])
    get "/knowledge_items/#{email.uuid}/edit"
    assert_response :success
    assert_includes @response.body, "data-copy-clipboard-content-value=\"{{name}}\""
    assert_not_includes @response.body, "data-copy-clipboard-content-value=\"{{anrede}}\"",
                        "E-Mail-Vorlage zeigt nur name/email/datum"
    assert_not_includes @response.body, "Infoblock-Feld", "Infoblock-Hinweis nur bei Dokumenttypen"

    plain = FileProxy.create(actor: @hans, title: "Normale Notiz", item_type: :note,
                             content: "", tags: [])
    get "/knowledge_items/#{plain.uuid}/edit"
    assert_response :success
    assert_not_includes @response.body, "data-copy-clipboard-content-value=\"{{",
                        "normale KIs bleiben ohne Platzhalter-Chips"
  end
end
