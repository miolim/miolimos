# #761 (Hans, 2026-06-23): Extrahiert strukturierte Kontaktdaten aus einer
# Webseite (typisch: Impressum/Kontaktseite). Holt die Seite über denselben
# Web-Clip-Fetch wie der Inbox-Importer und lässt ein LLM die Felder als JSON
# herausziehen. Bequeme Auslösung der Kontaktdaten-Phase der
# Entitäts-Recherche (siehe [[Verfahren: Entitäts-Recherche]]), wenn die
# Primärquelle (URL) schon vorliegt.
class ContactExtractor
  class Error < StandardError; end

  FIELDS = %w[organization email phone fax url vat_id register].freeze
  ADDRESS_FIELDS = %w[line1 line2 postal_code city country].freeze

  SYSTEM = "Du extrahierst Kontaktdaten aus dem Text einer Webseite " \
           "(z. B. einem Impressum). Antworte AUSSCHLIESSLICH mit einem " \
           "JSON-Objekt — keine Erklärung, kein Markdown, keine Code-Fences."

  # Liefert ein Hash mit Symbol-Keys: organization, email, phone, fax, url,
  # vat_id (Strings oder nil) + address (Hash line1/line2/postal_code/city/
  # country oder nil). llm/fetcher injizierbar für Tests.
  def self.call(url, fetcher: nil, llm: Llm::ChatClient)
    url = url.to_s.strip
    raise Error, "Keine URL" if url.empty?
    raise Error, "Ungültige URL" unless url.match?(%r{\Ahttps?://}i)

    text = (fetcher || method(:default_fetch)).call(url)
    raise Error, "Seite leer oder nicht erreichbar" if text.to_s.strip.empty?

    raw = llm.complete(
      system: SYSTEM,
      prompt: prompt_for(text.to_s.first(8000)),
      model:  nil,
      max_tokens: 700
    )
    parse(raw)
  end

  def self.default_fetch(url)
    clip = Inbox::Processors::WebClip.new
    html = clip.send(:fetch_html, url)
    clip.send(:extract_body, html, url)
  end

  def self.prompt_for(text)
    <<~PROMPT
      Extrahiere die Kontaktdaten der Person/Organisation aus folgendem
      Seitentext. Gib NUR Felder zurück, die eindeutig im Text stehen — sonst
      null. Telefon/Fax als zusammenhängende Nummer, USt-ID inkl. Länder-
      präfix. Schema (genau diese Schlüssel):

      {
        "organization": string|null,
        "email": string|null,
        "phone": string|null,
        "fax": string|null,
        "url": string|null,
        "vat_id": string|null,
        "register": string|null,
        "address": { "line1": string|null, "line2": string|null,
                     "postal_code": string|null, "city": string|null,
                     "country": string|null } | null
      }

      Bei "register" das Handelsregister inkl. Gericht und Nummer angeben,
      z. B. "Amtsgericht Lübeck HRB 12345" (sonst null).

      Seitentext:
      #{text}
    PROMPT
  end

  def self.parse(raw)
    json = raw.to_s.strip
    # Defensive: evtl. doch Code-Fences/Prosa drumherum → erstes {...} ziehen.
    json = json[/\{.*\}/m] || json
    data = JSON.parse(json)
    out = {}
    FIELDS.each { |f| out[f.to_sym] = data[f].to_s.strip.presence }
    addr = data["address"]
    if addr.is_a?(Hash)
      a = {}
      ADDRESS_FIELDS.each { |f| a[f.to_sym] = addr[f].to_s.strip.presence }
      out[:address] = a if a.values.any?
    end
    out
  rescue JSON::ParserError => e
    raise Error, "Antwort nicht lesbar: #{e.message}"
  end
end
