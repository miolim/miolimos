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
end
