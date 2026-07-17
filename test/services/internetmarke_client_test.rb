require "test_helper"
# BEWUSST nicht webmock/minitest: dessen Require-Hook schaltet
# disable_net_connect! prozessweit — und Ferrum (PDF) + lokales Ollama
# brauchen in anderen Tests echtes localhost-HTTP. Hier: plain webmock,
# scharf nur zwischen setup und teardown dieses einen Tests.
require "webmock"

# #1055: Der ECHTE Kaufpfad (Geld!) war bei 0 % — Portokassen-Login,
# Marken-Kauf, voucher_id-Parsing aus den wechselnden Response-Formen der
# DHL-API und der ZIP/PNG-Download. Inhalts-Assertions (Lehre aus #1056:
# dort steckten die Bugs im Inhalt, nicht in der Struktur). WebMock wird
# nur hier scharf geschaltet (setup/teardown), der Rest der Suite bleibt
# unberührt.
class InternetmarkeClientTest < ActiveSupport::TestCase
  include WebMock::API

  BASE = "https://api-eu.dhl.com/post/de/shipping/im/v1".freeze
  PNG_BYTES = "\x89PNG\r\n\x1a\nFAKE-MARKE".b.freeze

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!
    @credential = InternetmarkeCredential.new(
      actor: create_human, portokasse_email: "kasse@example.com",
      portokasse_password: "geheim", client_id: "cid-1", client_secret: "sec-1")
    @client = Internetmarke::Client.new(@credential)
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def stub_login!(wallet: 1500)
    stub_request(:post, "#{BASE}/user")
      .with(body: hash_including(
        "grant_type" => "client_credentials", "client_id" => "cid-1",
        "client_secret" => "sec-1", "username" => "kasse@example.com",
        "password" => "geheim"))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { access_token: "tok-123", walletBalance: wallet }.to_json)
  end

  def zip_with_png(name = "marke.png", bytes = PNG_BYTES)
    io = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry(name)
      zip.write(bytes)
    end
    io.string
  end

  def stub_checkout!(response_body, download: zip_with_png)
    stub_request(:post, "#{BASE}/app/shoppingcart/png")
      .with(headers: { "Authorization" => "Bearer tok-123" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: response_body.to_json)
    stub_request(:get, "https://download.example.com/marke.zip")
      .to_return(status: 200, body: download)
  end

  test "authenticate: Login-Form korrekt, Token + Wallet übernommen; ohne access_token klarer Fehler" do
    stub_login!(wallet: 815)
    res = @client.authenticate
    assert_equal "tok-123", res["access_token"]
    assert_equal 815, @client.wallet_balance

    WebMock.reset!
    stub_request(:post, "#{BASE}/user")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { error: "invalid_grant" }.to_json)
    err = assert_raises(Internetmarke::Client::Error) { Internetmarke::Client.new(@credential).authenticate }
    assert_match(/ohne access_token/, err.message)
  end

  test "buy_png: Kauf-Request trägt Produkt/Preis/AddressZone, PNG kommt aus dem ZIP, voucher_id + Wallet geparst" do
    stub_login!
    stub_checkout!({
      link: "https://download.example.com/marke.zip",
      walletBallance: 405,   # sic — die DHL-API schreibt Ballance
      shoppingCart: { voucherList: { voucher: [{ voucherId: "A0123456" }] } }
    })

    bought = @client.buy_png(product_code: 1, price_cents: 95)

    assert_equal "A0123456", bought[:voucher_id]
    assert_equal PNG_BYTES, bought[:png], "PNG muss unverändert aus dem ZIP kommen"
    assert_equal 405, bought[:wallet_balance], "walletBallance (DHL-Tippfehler) muss geparst werden"

    buy_request = WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                    .find { |sig| sig.uri.path.end_with?("/app/shoppingcart/png") }
    payload = JSON.parse(buy_request.body)
    assert_equal 95, payload["total"]
    assert_equal 1, payload.dig("positions", 0, "productCode")
    assert_equal "AddressZone", payload.dig("positions", 0, "voucherLayout")
  end

  test "buy_png: alternative Response-Formen (voucherList als Array, vouchers flach) liefern die voucher_id" do
    stub_login!
    stub_checkout!({ link: "https://download.example.com/marke.zip",
                     shoppingCart: { voucherList: [{ "voucherId" => "B99" }] } })
    assert_equal "B99", @client.buy_png(product_code: 1, price_cents: 95)[:voucher_id]

    WebMock.reset!
    stub_login!
    stub_checkout!({ link: "https://download.example.com/marke.zip",
                     vouchers: [{ "voucher_id" => "C77" }] })
    assert_equal "C77", Internetmarke::Client.new(@credential).buy_png(product_code: 1, price_cents: 95)[:voucher_id]
  end

  test "buy_png ohne Download-Link: klarer Fehler, kein stiller Geldverlust" do
    stub_login!
    stub_request(:post, "#{BASE}/app/shoppingcart/png")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { shoppingCart: {} }.to_json)
    err = assert_raises(Internetmarke::Client::Error) { @client.buy_png(product_code: 1, price_cents: 95) }
    assert_match(/ohne Download-Link/, err.message)
  end

  test "HTTP-Fehler (z. B. Wallet leer) wird mit Status + Body-Auszug gemeldet" do
    stub_login!
    stub_request(:post, "#{BASE}/app/shoppingcart/png")
      .to_return(status: 402, body: '{"detail":"insufficient wallet balance"}')
    err = assert_raises(Internetmarke::Client::Error) { @client.buy_png(product_code: 1, price_cents: 95) }
    assert_match(/HTTP 402/, err.message)
    assert_match(/insufficient wallet balance/, err.message)
  end

  test "ZIP ohne PNG und Nicht-JSON-Antworten geben klare Fehler" do
    stub_login!
    stub_checkout!({ link: "https://download.example.com/marke.zip",
                     shoppingCart: { voucherList: { voucher: [{ voucherId: "A1" }] } } },
                   download: zip_with_png("beleg.txt", "kein bild"))
    err = assert_raises(Internetmarke::Client::Error) { @client.buy_png(product_code: 1, price_cents: 95) }
    assert_match(/ZIP ohne PNG/, err.message)

    WebMock.reset!
    stub_request(:post, "#{BASE}/user").to_return(status: 200, body: "<html>Wartung</html>")
    err = assert_raises(Internetmarke::Client::Error) { Internetmarke::Client.new(@credential).authenticate }
    assert_match(/Keine JSON-Antwort/, err.message)
  end

  test "Direkt-PNG (ohne ZIP) hinter dem Link wird akzeptiert" do
    stub_login!
    stub_checkout!({ link: "https://download.example.com/marke.zip",
                     shoppingCart: { voucherList: { voucher: [{ voucherId: "A1" }] } } },
                   download: PNG_BYTES)
    assert_equal PNG_BYTES, @client.buy_png(product_code: 1, price_cents: 95)[:png]
  end
end
