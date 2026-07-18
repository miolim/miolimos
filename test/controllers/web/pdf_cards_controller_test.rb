require "test_helper"

# #1025 (aus immoos übernommen, #1057): PDFs (PDF-Stände, Belege) als
# Stack-Card öffnen.
class PdfCardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-pdf-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret", role: :admin)
    grant(@hans, "Task", %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def payload(path, title = nil)
    Base64.urlsafe_encode64([path, title].compact.join("\n"), padding: false)
  end

  test "rendert die PDF-Card mit eingebettetem Pfad und Titel" do
    get pdf_card_path(payload("/invoices/1/artifacts/2", "Beleg 2026-001"))
    assert_response :success
    assert_includes @response.body, %(embed src="/invoices/1/artifacts/2")
    assert_includes @response.body, "Beleg 2026-001"
    assert_includes @response.body, "stack_card_pdfcard:"
    # Fallback-Link „im Browser-Tab öffnen" bleibt erhalten.
    assert_includes @response.body, %(href="/invoices/1/artifacts/2")
  end

  test "externe/protokoll-relative URLs werden abgelehnt" do
    get pdf_card_path(payload("https://boese.example/x.pdf"))
    assert_response :not_found
    get pdf_card_path(payload("//boese.example/x.pdf"))
    assert_response :not_found
    get pdf_card_path("kein-base64-%%%")
    assert_response :not_found
  end
end
