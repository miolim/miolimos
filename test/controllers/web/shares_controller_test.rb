require "test_helper"

# #634: Android-Share-Target — POST /share legt Inbox-Einträge an.
class SharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    grant(@hans, "InboxItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "geteilte URL → web_url-Item, YouTube → youtube_url" do
    assert_difference -> { InboxItem.count }, 1 do
      post "/share", params: { url: "https://example.com/artikel" }
    end
    assert_equal "web_url", InboxItem.last.source_kind

    post "/share", params: { url: "https://www.youtube.com/watch?v=abc12345678" }
    assert_equal "youtube_url", InboxItem.last.source_kind
    assert_response :redirect
    assert_includes @response.redirect_url, "inboxitem%3A#{InboxItem.last.id}"
  end

  test "URL im text-Feld (YouTube-App-Stil) wird extrahiert" do
    post "/share", params: { text: "Schau mal: https://youtu.be/abc12345678 cool!", title: "Video-Tipp" }
    item = InboxItem.last
    assert_equal "youtube_url", item.source_kind
    assert_equal "https://youtu.be/abc12345678", item.source_url
    assert_equal "Video-Tipp", item.title
  end

  test "reiner Text → text-Item; leerer Share → 400" do
    post "/share", params: { title: "Gedanke", text: "Nur eine Notiz." }
    item = InboxItem.last
    assert_equal "text", item.source_kind
    assert_includes item.raw_content, "Nur eine Notiz."

    post "/share", params: {}
    assert_response :bad_request
  end

  test "geteilte Datei → upload-Item" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("PDFDATA"), "application/pdf", original_filename: "beleg.pdf"
    )
    assert_difference -> { InboxItem.count }, 1 do
      post "/share", params: { file: file }
    end
    item = InboxItem.last
    assert_equal "pdf_upload", item.source_kind
    assert_equal "beleg", item.title
  ensure
    item = InboxItem.last
    File.delete(item.external_path) if item&.external_path && File.exist?(item.external_path)
  end

  test "ohne Login: Redirect zum Login; ohne Capability: 403" do
    delete "/logout"
    post "/share", params: { url: "https://example.com" }
    assert_response :redirect
    assert_includes @response.redirect_url, "/login"

    reader = create_human(name: "Ohne", password: "secretsecret")
    post "/login", params: { email: reader.email, password: "secretsecret" }
    post "/share", params: { url: "https://example.com" }
    assert_response :forbidden
  end

  test "manifest + service worker liegen unter den erwarteten Pfaden" do
    get "/manifest.webmanifest"
    assert_response :success
    manifest = JSON.parse(@response.body)
    assert_equal "/share", manifest.dig("share_target", "action")
    get "/service-worker.js"
    assert_response :success
  end
end
