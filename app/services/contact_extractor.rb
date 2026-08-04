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

  SYSTEM = "Du extrahierst Kontaktdaten aus einem Text — einem Impressum, " \
           "einer E-Mail-Signatur, einer Visitenkarte. Antworte AUSSCHLIESSLICH " \
           "mit einem JSON-Objekt — keine Erklärung, kein Markdown, keine Code-Fences."

  # Liefert ein Hash mit Symbol-Keys: organization, email, phone, fax, url,
  # vat_id (Strings oder nil) + address (Hash line1/line2/postal_code/city/
  # country oder nil). llm/fetcher injizierbar für Tests.
  def self.call(url, fetcher: nil, llm: Llm::ChatClient)
    url = url.to_s.strip
    raise Error, "Keine URL" if url.empty?
    raise Error, "Ungültige URL" unless url.match?(%r{\Ahttps?://}i)

    text = (fetcher || method(:default_fetch)).call(url)
    raise Error, "Seite leer oder nicht erreichbar" if text.to_s.strip.empty?
    # Bewusst OHNE die Wörtlichkeits-Prüfung von from_text: Impressen
    # verschleiern Adressen gern („info(at)firma.de", „info [ät] firma punkt
    # de"), und das Auflösen ist hier ein Gewinn, kein Erfinden.
    extract(text, llm: llm)
  end

  # #1250 (Hans, 2026-08-04): derselbe Weg für eingefügten Freitext — eine
  # kopierte E-Mail-Signatur, ein Visitenkarten-Text. Die Beschaffung fällt
  # weg, das Herauslesen ist identisch.
  #
  # Warum überhaupt ein Modell und nicht nur Muster: E-Mail, Telefon, USt-ID
  # und PLZ sind mit Regeln zuverlässig zu FINDEN — aber nicht zu DEUTEN.
  # Ob „+49 4321 55" die Zentrale, das Fax oder das Mobiltelefon ist, ob eine
  # Zeile Firma, Rolle oder Straße meint, steht nirgends im Muster, sondern
  # nur in der Anordnung, und die hat jede Signatur anders. Genau diese
  # Zuordnung übernimmt das Modell.
  #
  # Umgekehrt gilt: Was ein Muster prüfen KANN, soll es auch prüfen — siehe
  # verify_verbatim!. Ein Modell, das eine Ziffer „glättet", liefert eine
  # plausible und falsche Telefonnummer, und die fällt niemandem auf.
  def self.from_text(text, llm: Llm::ChatClient)
    raise Error, "Kein Text" if text.to_s.strip.empty?
    quelle = text.to_s.first(8000)
    verify_verbatim!(extract(quelle, llm: llm), quelle)
  end

  # Der gemeinsame Kern beider Wege: Text rein, Felder raus.
  def self.extract(text, llm: Llm::ChatClient)
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

  # #1250: Felder, die im Quelltext WÖRTLICH vorkommen müssen. Sie haben eine
  # prüfbare Form, und bei ihnen ist eine plausible Erfindung schlimmer als
  # eine Lücke: Eine erfundene E-Mail-Adresse sieht richtig aus und Post geht
  # an Fremde. Was das Modell nicht belegen kann, fliegt raus — der Rest
  # (Organisation, Adresse) darf normalisiert werden, dort ist Umschreiben
  # gewollt („Str." → „Straße").
  #
  # Telefon/Fax werden auf die Ziffernfolge reduziert verglichen: „+49 4321
  # 55-0" und „04321/55-0" sind dieselbe Nummer, unterschiedlich geschrieben —
  # die Formatierung darf das Modell vereinheitlichen, die Ziffern nicht.
  def self.verify_verbatim!(data, quelle)
    haystack = quelle.to_s.downcase
    ziffern  = haystack.gsub(/\D/, "")

    # E-Mail: streng. Eine Adresse hat keine legitime Schreibvariante außer
    # Groß-/Kleinschreibung.
    if (mail = data[:email].to_s.strip).present?
      data[:email] = nil unless haystack.include?(mail.downcase)
    end

    # USt-IdNr: Leerzeichen und Punkte sind Schreibweise, nicht Inhalt
    # („DE 123 456 789" ist dieselbe Nummer wie „DE123456789").
    if (vat = data[:vat_id].to_s.strip).present?
      kompakt = ->(s) { s.downcase.gsub(/[\s.\-\/]/, "") }
      data[:vat_id] = nil unless kompakt.call(haystack).include?(kompakt.call(vat))
    end

    # Die URL bleibt bewusst ungeprüft: „www.example.com" im Text und
    # „https://www.example.com" in der Antwort sind dieselbe Adresse, nur
    # vervollständigt — und eine falsche Webadresse richtet keinen Schaden
    # an, der eine Verschärfung rechtfertigt (anders als eine E-Mail, an
    # die dann Post geht).

    %i[phone fax].each do |feld|
      wert = data[feld].to_s.strip
      next if wert.blank?
      nur_ziffern = wert.gsub(/\D/, "")
      # Führende Null der nationalen Schreibweise entspricht der Vorwahl mit
      # Ländercode („+49 4321…" ↔ „04321…") — beide Lesarten zulassen.
      varianten = [nur_ziffern, nur_ziffern.sub(/\A0/, "")].uniq.reject(&:blank?)
      data[feld] = nil unless varianten.any? { |v| ziffern.include?(v) }
    end

    data
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
