require "test_helper"

# #609: Editor-Paste-Upload — Bild aus der Zwischenablage wird als
# Bild-KI angelegt; das JS fügt ![[Titel]] am Cursor ein.
class ImagePasteTest < ActionDispatch::IntegrationTest
  PNG = "\x89PNG\r\n\x1a\n".b + "fake-image-bytes".b

  setup do
    @hans = create_human(password: "secretsecret")
    %w[KnowledgeItem Topic].each { |rt| grant(@hans, rt, %w[read create update delete]) }
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def upload!(title: nil)
    file = Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", original_filename: "shot.png")
    post "/knowledge_items/paste_image", params: { file: file, title: title }.compact
  end

  test "legt Bild-KI an und liefert Titel/UUID" do
    upload!
    assert_response :success
    body = JSON.parse(response.body)
    item = KnowledgeItem.find(body["uuid"])
    assert_match(/\AScreenshot /, body["title"])
    assert item.file_path.end_with?(".png")
    # Datei liegt auf Platte und kommt über /file zurück
    get "/knowledge_items/#{item.uuid}/file"
    assert_response :success
  end

  test "titel-kollision bekommt suffix" do
    upload!(title: "Mein Screenshot")
    upload!(title: "Mein Screenshot")
    titles = KnowledgeItem.where("title LIKE 'Mein Screenshot%'").pluck(:title).sort
    assert_equal ["Mein Screenshot", "Mein Screenshot (2)"], titles
  end
end
