require "test_helper"

# #547 (Hans, 2026-06-08): Unterschriftsbild-Verwaltung.
class Settings::SignaturesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-sig-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Actor", %w[read update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET zeigt die Unterschrift-Seite" do
    get "/settings/signature"
    follow_redirect!   # #613: Reiter-URL leitet auf den Stack
    assert_response :success
    assert_includes @response.body, "Unterschrift"
  end

  test "Upload speichert das Bild als Data-URI; destroy entfernt es" do
    png = "\x89PNG\r\n\x1a\nFAKE".b
    file = Rack::Test::UploadedFile.new(StringIO.new(png), "image/png", original_filename: "sig.png")
    patch "/settings/signature", params: { signature: file }
    assert_redirected_to settings_signature_path
    sig = @hans.reload.signature_image
    assert sig&.start_with?("data:image/png;base64,"), "kein Data-URI gespeichert"

    delete "/settings/signature"
    assert_nil @hans.reload.signature_image
  end

  test "lehnt Nicht-Bilder ab" do
    file = Rack::Test::UploadedFile.new(StringIO.new("nope"), "text/plain", original_filename: "x.txt")
    patch "/settings/signature", params: { signature: file }
    assert_redirected_to settings_signature_path
    assert_nil @hans.reload.signature_image
  end
end
