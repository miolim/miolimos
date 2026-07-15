require "test_helper"

# #995: Frankieren über das Detail-Blade — Dummy-Marke (ohne Portokasse),
# Entfernen, Gate für nicht-frankierbare Dokumente, Settings-Credentials.
class FrankingTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "frank-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret", role: :admin
    )
    grant(@hans, "Task",  %w[read create update delete])   # Gate der Printables (V1)
    grant(@hans, "Actor", %w[read update])                 # Settings-Gate
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "Dummy-Frankierung setzt Marke, sie erscheint im gerenderten Brief" do
    doc = Document.create!(kind: :brief)
    post franking_document_path(doc), params: { product: 1, dummy: 1 }
    assert_response :see_other

    voucher = doc.reload.postage_voucher
    assert voucher.dummy?
    assert_equal "Standardbrief", voucher.product_label
    assert_nil voucher.voucher_id

    get document_path(doc)
    assert_response :success
    assert_includes @response.body, "din-franking"

    delete franking_document_path(doc)
    assert_nil doc.reload.postage_voucher
  end

  test "Neufrankieren ersetzt die vorhandene Marke" do
    doc = Document.create!(kind: :brief)
    post franking_document_path(doc), params: { product: 1, dummy: 1 }
    post franking_document_path(doc), params: { product: 21, dummy: 1 }
    assert_equal 1, PostageVoucher.where(printable: doc).count
    assert_equal "Großbrief", doc.reload.postage_voucher.product_label
  end

  test "NDA (ohne DIN-Fenster) ist nicht frankierbar" do
    doc = Document.create!(kind: :nda)
    post franking_document_path(doc), params: { product: 1, dummy: 1 }
    assert_nil doc.reload.postage_voucher
  end

  test "eingehende Rechnung ist nicht frankierbar, ausgehende schon" do
    incoming = Invoice.create!(kind: :rechnung, direction: :eingehend)
    post franking_invoice_path(incoming), params: { product: 1, dummy: 1 }
    assert_nil incoming.reload.postage_voucher

    outgoing = Invoice.create!(kind: :rechnung)
    post franking_invoice_path(outgoing), params: { product: 1, dummy: 1 }
    assert outgoing.reload.postage_voucher&.dummy?
  end

  test "echte Frankierung ohne Zugangsdaten liefert Hinweis statt Kauf" do
    doc = Document.create!(kind: :brief)
    post franking_document_path(doc), params: { product: 1 }
    assert_nil doc.reload.postage_voucher
  end

  test "Settings speichern Credentials verschlüsselt; leere Secrets bleiben erhalten" do
    patch settings_internetmarke_path, params: {
      portokasse_email: "post@t.local", portokasse_password: "geheim",
      client_id: "cid", client_secret: "csecret"
    }
    cred = @hans.reload.internetmarke_credential
    assert_equal "geheim", cred.portokasse_password
    refute_nil cred.portokasse_password_ciphertext

    patch settings_internetmarke_path, params: {
      portokasse_email: "neu@t.local", portokasse_password: "",
      client_id: "cid", client_secret: ""
    }
    cred.reload
    assert_equal "neu@t.local", cred.portokasse_email
    assert_equal "geheim", cred.portokasse_password   # blank = unverändert
    assert_equal "csecret", cred.client_secret
  end
end
