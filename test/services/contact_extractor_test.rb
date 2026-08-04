require "test_helper"

class ContactExtractorTest < ActiveSupport::TestCase
  # Fake-LLM: liefert eine feste Roh-Antwort, damit wir Fetch + Parsing
  # ohne echten API-Call testen.
  def fake_llm(raw)
    Class.new do
      define_singleton_method(:complete) { |**| raw }
    end
  end

  test "parst sauberes JSON in Felder + Adresse" do
    raw = '{"organization":"Smart Up Technology","email":"info@smartup.email",' \
          '"phone":"0177 95 77 538","fax":null,"url":"https://smart-up-technology.de",' \
          '"vat_id":"DE327179803","address":{"line1":"Schwartauer Str. 56","line2":null,' \
          '"postal_code":"23611","city":"Sereetz","country":null}}'
    out = ContactExtractor.call("https://example.com/impressum",
                                fetcher: ->(_) { "irgendein Seitentext" },
                                llm: fake_llm(raw))
    assert_equal "info@smartup.email", out[:email]
    assert_equal "DE327179803",        out[:vat_id]
    assert_nil out[:fax]   # null bleibt nil
    assert_equal "Schwartauer Str. 56", out[:address][:line1]
    assert_equal "23611",               out[:address][:postal_code]
    assert_equal "Sereetz",             out[:address][:city]
  end

  test "zieht JSON aus Antwort mit Code-Fences/Prosa" do
    raw = "Hier die Daten:\n```json\n{\"email\":\"a@b.io\"}\n```\n"
    out = ContactExtractor.call("https://example.com",
                                fetcher: ->(_) { "text" }, llm: fake_llm(raw))
    assert_equal "a@b.io", out[:email]
  end

  test "leere Seite -> Error" do
    assert_raises(ContactExtractor::Error) do
      ContactExtractor.call("https://example.com", fetcher: ->(_) { "" }, llm: fake_llm("{}"))
    end
  end

  test "unleserliche LLM-Antwort -> Error" do
    assert_raises(ContactExtractor::Error) do
      ContactExtractor.call("https://example.com", fetcher: ->(_) { "text" }, llm: fake_llm("kein json"))
    end
  end

  test "ungültige URL -> Error" do
    assert_raises(ContactExtractor::Error) { ContactExtractor.call("nicht-url", llm: fake_llm("{}")) }
  end

  # ── #1250: eingefügter Freitext (E-Mail-Signatur) ────────────────────

  SIGNATUR = <<~TXT
    Mit freundlichen Grüßen
    Dr. Erika Mustermann
    Leiterin Vertrieb

    Musterbau GmbH
    Schwartauer Str. 56
    23611 Sereetz

    Tel.: +49 4321 55-0
    Fax:  +49 4321 55-99
    erika.mustermann@musterbau.de
    www.musterbau.de
    USt-IdNr.: DE 123 456 789
  TXT

  test "#1250 aus einer eingefügten Signatur werden die Felder übernommen" do
    raw = '{"organization":"Musterbau GmbH","email":"erika.mustermann@musterbau.de",' \
          '"phone":"+49 4321 55-0","fax":"+49 4321 55-99","url":"https://www.musterbau.de",' \
          '"vat_id":"DE123456789","address":{"line1":"Schwartauer Str. 56",' \
          '"postal_code":"23611","city":"Sereetz"}}'
    out = ContactExtractor.from_text(SIGNATUR, llm: fake_llm(raw))
    assert_equal "erika.mustermann@musterbau.de", out[:email]
    assert_equal "Musterbau GmbH", out[:organization]
    assert_equal "23611", out[:address][:postal_code]
  end

  test "#1250 leerer Text -> Error" do
    assert_raises(ContactExtractor::Error) { ContactExtractor.from_text("   ", llm: fake_llm("{}")) }
  end

  # Der eigentliche Grund für die Wörtlichkeits-Prüfung: Ein Modell, das eine
  # Adresse „glättet" oder eine Ziffer verdreht, liefert etwas Plausibles und
  # Falsches — und das fällt niemandem auf. Lieber ein leeres Feld.
  test "#1250 eine nicht im Text belegte E-Mail wird verworfen" do
    raw = '{"email":"info@musterbau.de"}'   # steht so NICHT in der Signatur
    out = ContactExtractor.from_text(SIGNATUR, llm: fake_llm(raw))
    assert_nil out[:email], "erfundene Adresse darf nicht durchkommen"
  end

  test "#1250 eine erfundene Telefonnummer wird verworfen" do
    raw = '{"phone":"+49 4321 55-77"}'      # Ziffernfolge kommt im Text nicht vor
    assert_nil ContactExtractor.from_text(SIGNATUR, llm: fake_llm(raw))[:phone]
  end

  test "#1250 andere Schreibweise derselben Nummer bleibt erhalten" do
    # Dieselbe Nummer, national statt international geschrieben: das ist
    # Formatierung, kein anderer Inhalt.
    raw = '{"phone":"04321 55-0","fax":"04321/5599"}'
    out = ContactExtractor.from_text(SIGNATUR, llm: fake_llm(raw))
    assert_equal "04321 55-0", out[:phone]
    assert_equal "04321/5599", out[:fax]
  end

  test "#1250 USt-IdNr darf zusammengezogen werden, Erfundenes nicht" do
    out = ContactExtractor.from_text(SIGNATUR, llm: fake_llm('{"vat_id":"DE123456789"}'))
    assert_equal "DE123456789", out[:vat_id], "nur Leerzeichen entfernt — dieselbe Nummer"

    out = ContactExtractor.from_text(SIGNATUR, llm: fake_llm('{"vat_id":"DE999888777"}'))
    assert_nil out[:vat_id]
  end

  test "#1250 die vervollständigte Web-Adresse bleibt erhalten" do
    # „www.musterbau.de" im Text, „https://…" in der Antwort: dieselbe
    # Adresse, nur vollständig — und harmlos, falls doch daneben.
    out = ContactExtractor.from_text(SIGNATUR, llm: fake_llm('{"url":"https://www.musterbau.de"}'))
    assert_equal "https://www.musterbau.de", out[:url]
  end

  # Der URL-Weg bleibt bewusst nachsichtig: Impressen verschleiern Adressen,
  # und das Auflösen ist dort erwünscht.
  test "#1250 der URL-Weg prüft NICHT auf Wörtlichkeit (Obfuskation)" do
    seite = "Kontakt: info (at) musterbau punkt de"
    out = ContactExtractor.call("https://example.com/impressum",
                                fetcher: ->(_) { seite },
                                llm: fake_llm('{"email":"info@musterbau.de"}'))
    assert_equal "info@musterbau.de", out[:email],
                 "die aufgeloeste Adresse ist hier ein Gewinn, kein Erfinden"
  end
end
