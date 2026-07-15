# #995: Client für die Deutsche-Post-INTERNETMARKE-REST-API
# (developer.dhl.com, Basis https://api-eu.dhl.com/post/de/shipping/im/v1).
# Auth: OAuth2 client_credentials + Portokassen-Login (POST /user), Kauf:
# POST /app/shoppingcart/png → Link auf ZIP mit dem Marken-PNG.
#
# ACHTUNG: Der Live-Pfad ist nach der öffentlichen API-Referenz gebaut,
# aber noch UNGETESTET — es liegen keine Portokassen-Zugangsdaten vor
# (Task #995). Vor dem ersten Echt-Kauf: #catalog prüfen und einen
# 0,95-€-Kauf verifizieren. Fehler kommen als Client::Error mit
# HTTP-Status + gekürztem Response-Body.
require "net/http"

module Internetmarke
  class Client
    class Error < StandardError; end

    BASE = URI(ENV.fetch("INTERNETMARKE_API_BASE",
                          "https://api-eu.dhl.com/post/de/shipping/im/v1"))
    # Marke im Layout fürs Adressfeld (statt Frankierzone rechts oben).
    VOUCHER_LAYOUT = "AddressZone"

    def initialize(credential)
      @credential = credential
    end

    # Portokassen-Login; liefert Bearer-Token + Wallet-Stand (Cents).
    def authenticate
      res = post_form("/user",
        "grant_type"    => "client_credentials",
        "client_id"     => @credential.client_id,
        "client_secret" => @credential.client_secret,
        "username"      => @credential.portokasse_email,
        "password"      => @credential.portokasse_password)
      @token = res["access_token"] or raise Error, "Login ohne access_token: #{res.keys.join(', ')}"
      @wallet_balance = res["walletBalance"] || res["wallet_balance"]
      res
    end

    def wallet_balance = @wallet_balance

    # Produktkatalog (zur Verifikation der productCodes in PRODUCTS).
    def catalog
      authenticate unless @token
      get_json("/app/catalog?types=PPL")
    end

    # Kauft EINE Marke und liefert { voucher_id:, png:, wallet_balance: }.
    def buy_png(product_code:, price_cents:)
      authenticate unless @token
      body = {
        type: "AppShoppingCartPNGRequest",
        total: price_cents,
        positions: [{
          productCode:   product_code,
          voucherLayout: VOUCHER_LAYOUT,
          position: { labelX: 1, labelY: 1, page: 1 }
        }]
      }
      res = post_json("/app/shoppingcart/png", body)
      vouchers = Array(res.dig("shoppingCart", "voucherList", "voucher") ||
                       res.dig("shoppingCart", "voucherList") || res["vouchers"])
      voucher_id = vouchers.filter_map { |v| v["voucherId"] || v["voucher_id"] }.first
      link = res["link"] or raise Error, "Checkout ohne Download-Link: #{res.keys.join(', ')}"
      {
        voucher_id: voucher_id,
        png: fetch_png(link),
        wallet_balance: res["walletBallance"] || res["walletBalance"]
      }
    end

    private

    # Die Marke kommt als ZIP (ein PNG pro Voucher) hinter dem Link.
    def fetch_png(link)
      raw = http_get_raw(URI(link))
      if raw.byteslice(0, 4) == "PK\x03\x04"
        Zip::File.open_buffer(StringIO.new(raw)) do |zip|
          entry = zip.glob("*.png").first || zip.entries.find { |e| e.name.end_with?(".png") }
          raise Error, "ZIP ohne PNG (#{zip.entries.map(&:name).join(', ')})" unless entry
          return entry.get_input_stream.read
        end
      elsif raw.byteslice(1, 3) == "PNG"
        raw
      else
        raise Error, "Unerwartetes Download-Format hinter #{link}"
      end
    end

    def post_form(path, params)
      req = Net::HTTP::Post.new(BASE.path + path)
      req.set_form_data(params)
      request_json(req)
    end

    def post_json(path, body)
      req = Net::HTTP::Post.new(BASE.path + path)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)
      request_json(req)
    end

    def get_json(path)
      request_json(Net::HTTP::Get.new(BASE.path + path))
    end

    def request_json(req)
      req["Accept"]        = "application/json"
      req["Authorization"] = "Bearer #{@token}" if @token
      res = Net::HTTP.start(BASE.host, BASE.port, use_ssl: true,
                            open_timeout: 10, read_timeout: 30) { |h| h.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        raise Error, "HTTP #{res.code} auf #{req.path}: #{res.body.to_s.byteslice(0, 300)}"
      end
      JSON.parse(res.body)
    rescue JSON::ParserError
      raise Error, "Keine JSON-Antwort auf #{req.path}"
    end

    def http_get_raw(uri, limit = 3)
      raise Error, "Zu viele Redirects beim Marken-Download" if limit.zero?
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                            open_timeout: 10, read_timeout: 30) { |h| h.request(Net::HTTP::Get.new(uri)) }
      return http_get_raw(URI(res["location"]), limit - 1) if res.is_a?(Net::HTTPRedirection)
      raise Error, "Marken-Download fehlgeschlagen (HTTP #{res.code})" unless res.is_a?(Net::HTTPSuccess)
      res.body
    end
  end
end
