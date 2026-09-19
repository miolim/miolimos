require "net/http"
require "resolv"
require "ipaddr"

# #1675: DER Abruf fremder Web-Adressen (Web-Clip, Markdown-Import, Titel holen,
# Kontakt-Extraktion). Vorher stand an jeder Stelle ein eigenes Net::HTTP — und
# keine prüfte, WOHIN sie abruft. Eine Adresse kommt vom Nutzer, von einem
# Agenten oder aus einer Mail; `http://127.0.0.1:5432/`, `http://169.254.169.254/`
# (Cloud-Metadaten) oder ein Gerät im Heimnetz wurden genauso abgerufen wie eine
# Zeitungsseite, und die Antwort landete lesbar in einem Wissenseintrag.
#
#   • nur http/https
#   • das Ziel — und JEDES Weiterleitungsziel — muss eine öffentliche Adresse
#     sein; verbunden wird mit genau der geprüften IP (kein zweites Auflösen
#     zwischen Prüfung und Verbindung)
#   • relative Weiterleitungen werden aufgelöst (#1462)
#   • Größengrenze: gelesen wird höchstens max_bytes
class SafeHttp
  class Error   < StandardError; end
  class Blocked < Error; end

  MAX_BYTES     = 10 * 1024 * 1024
  MAX_REDIRECTS = 5

  # Nicht öffentlich: Loopback, private Netze, Link-Local (inkl. Metadaten-
  # Dienst), CGNAT, Multicast/Reserviert, „diese Maschine", IPv6-Pendants.
  GESPERRT = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
    192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/3
    ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
  ].map { |netz| IPAddr.new(netz) }.freeze

  Antwort = Struct.new(:body, :uri, :content_type, keyword_init: true)

  class << self
    # Tests mit lokalem Testserver (WEBrick auf 127.0.0.1) öffnen die Sperre
    # ausdrücklich und nur für ihren Block — sie ist nie pauschal aus.
    def intern_erlaubt
      alt = Thread.current[:safe_http_intern]
      Thread.current[:safe_http_intern] = true
      yield
    ensure
      Thread.current[:safe_http_intern] = alt
    end

    def get(url, headers: {}, open_timeout: 5, read_timeout: 10, max_bytes: MAX_BYTES, max_redirects: MAX_REDIRECTS)
      uri = parse(url)
      (max_redirects + 1).times do
        res, body = anfrage(uri, headers, open_timeout, read_timeout, max_bytes)
        case res
        when Net::HTTPSuccess
          return Antwort.new(body: body, uri: uri, content_type: res["content-type"].to_s)
        when Net::HTTPRedirection
          ziel = res["location"].to_s
          raise Error, "Weiterleitung ohne Ziel (HTTP #{res.code}) fuer #{uri}" if ziel.empty?
          uri = parse(URI.join(uri, ziel).to_s, weiterleitung: true)
        else
          raise Error, "HTTP #{res.code} für #{url}"
        end
      end
      raise Error, "Zu viele Redirects für #{url}"
    end

    # Die öffentliche IP, mit der verbunden werden darf — oder Blocked.
    def pruefe_ziel!(host)
      adressen = begin
        IPAddr.new(host) && [host]
      rescue IPAddr::InvalidAddressError
        Resolv.getaddresses(host)
      end
      raise Error, "Adresse nicht auflösbar: #{host}" if adressen.empty?
      return adressen.first if Thread.current[:safe_http_intern]

      verboten = adressen.find { |a| gesperrt?(a) }
      raise Blocked, "#{host} zeigt auf eine interne Adresse (#{verboten}) und wird nicht abgerufen" if verboten
      adressen.first
    end

    def gesperrt?(adresse)
      ip = IPAddr.new(adresse.to_s.sub(/%.*\z/, ""))   # fe80::1%eth0
      ip = ip.native if ip.ipv4_mapped?
      GESPERRT.any? { |netz| netz.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end

    private

    def parse(url, weiterleitung: false)
      uri = URI.parse(url.to_s.strip)
      unless uri.is_a?(URI::HTTP) && uri.host.present?
        was = weiterleitung ? "Weiterleitung auf" : "Kein Web-Aufruf:"
        raise Error, "#{was} #{uri.scheme.presence || 'unbekanntes Schema'}: #{uri}"
      end
      uri
    rescue URI::InvalidURIError => e
      raise Error, "Ungültige Adresse: #{e.message}"
    end

    def anfrage(uri, headers, open_timeout, read_timeout, max_bytes)
      host = uri.host.to_s.delete_prefix("[").delete_suffix("]")
      http = Net::HTTP.new(host, uri.port)
      http.ipaddr       = pruefe_ziel!(host)   # mit der GEPRÜFTEN Adresse verbinden
      http.use_ssl      = uri.scheme == "https"
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      body = +""
      res = http.start do |verbindung|
        verbindung.request(Net::HTTP::Get.new(uri, headers)) do |antwort|
          next unless antwort.is_a?(Net::HTTPSuccess)
          antwort.read_body do |stueck|
            body << stueck
            raise Error, "Antwort größer als #{max_bytes / 1024 / 1024} MB — abgebrochen: #{uri}" if body.bytesize > max_bytes
          end
        end
      end
      [res, body]
    end
  end
end
