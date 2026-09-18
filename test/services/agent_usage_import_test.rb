require "test_helper"

# #1660: Der Import liest die Sitzungsprotokolle der Agenten und verdichtet
# den Verbrauch nach Tag, Projekt, Aufgabe und Modell. Geprüft wird an einem
# selbst geschriebenen Protokoll — echte Protokolle liegen außerhalb des
# Repos und wären als Testdaten weder stabil noch teilbar.
class AgentUsageImportTest < ActiveSupport::TestCase
  def protokoll_schreiben(verzeichnis, zeilen)
    projekt = verzeichnis.join("-home-hans")
    FileUtils.mkdir_p(projekt)
    datei = projekt.join("sitzung.jsonl")
    File.write(datei, zeilen.map { |z| JSON.generate(z) }.join("\n") + "\n")
    datei
  end

  def nutzer(text, zeit)
    { "type" => "user", "timestamp" => zeit.iso8601,
      "message" => { "role" => "user", "content" => text } }
  end

  def antwort(zeit, ein: 0, cache_neu: 0, cache_gelesen: 0, aus: 0, model: "claude-opus-5")
    { "type" => "assistant", "timestamp" => zeit.iso8601,
      "message" => { "model" => model,
                     "usage" => { "input_tokens" => ein,
                                  "cache_creation_input_tokens" => cache_neu,
                                  "cache_read_input_tokens" => cache_gelesen,
                                  "output_tokens" => aus } } }
  end

  test "verdichtet je Tag, Projekt, Aufgabe und Modell" do
    Dir.mktmpdir do |dir|
      basis = Pathname.new(dir)
      jetzt = Time.current
      protokoll_schreiben(basis, [
        antwort(jetzt, ein: 10, cache_gelesen: 1_000, aus: 100),                       # vor dem ersten Auslöser
        nutzer("Inbox-Check für miolim_builder [Auslöser: Aufgabe #1660 veröffentlicht]", jetzt),
        antwort(jetzt, cache_neu: 5_000, cache_gelesen: 20_000, aus: 300),
        antwort(jetzt, cache_gelesen: 30_000, aus: 200),
        nutzer("Inbox-Check [Auslöser: Neue Antwort auf Aufgabe #1642]", jetzt),
        antwort(jetzt, cache_gelesen: 7_000, aus: 50, model: "claude-haiku-4-5")
      ])

      ergebnis = AgentUsage::Import.call(tage: 3, basis: basis)
      assert_equal 1, ergebnis[:dateien]

      zu_1660 = AgentUsage.find_by(aufgabe: "1660")
      assert_equal 2, zu_1660.antworten
      assert_equal 50_000, zu_1660.cache_read_tokens
      assert_equal 5_000, zu_1660.cache_creation_tokens
      assert_equal 500, zu_1660.output_tokens
      assert_equal "-home-hans", zu_1660.projekt

      zu_1642 = AgentUsage.find_by(aufgabe: "1642")
      assert_equal "claude-haiku-4-5", zu_1642.model, "das Modell zählt je Antwort, nicht je Sitzung"

      ohne = AgentUsage.find_by(aufgabe: nil)
      assert_equal 1, ohne.antworten, "Verbrauch vor der ersten Auslöser-Zeile gehört zu keiner Aufgabe"
    end
  end

  test "ein zweiter Lauf verdoppelt nichts" do
    Dir.mktmpdir do |dir|
      basis = Pathname.new(dir)
      jetzt = Time.current
      protokoll_schreiben(basis, [
        nutzer("Inbox-Check [Auslöser: Aufgabe #1660]", jetzt),
        antwort(jetzt, cache_gelesen: 10_000, aus: 100)
      ])

      2.times { AgentUsage::Import.call(tage: 3, basis: basis) }

      zeilen = AgentUsage.where(aufgabe: "1660")
      assert_equal 1, zeilen.count
      assert_equal 10_000, zeilen.first.cache_read_tokens
      assert_equal 1, zeilen.first.antworten
    end
  end

  test "Zeilen ausserhalb des Zeitraums bleiben draussen" do
    Dir.mktmpdir do |dir|
      basis = Pathname.new(dir)
      alt = 10.days.ago
      protokoll_schreiben(basis, [
        nutzer("Inbox-Check [Auslöser: Aufgabe #1000]", alt),
        antwort(alt, cache_gelesen: 99_000, aus: 10)
      ])

      AgentUsage::Import.call(tage: 3, basis: basis)
      assert_nil AgentUsage.find_by(aufgabe: "1000")
    end
  end

  test "fehlendes Verzeichnis ist kein Fehler" do
    ergebnis = AgentUsage::Import.call(tage: 3, basis: Pathname.new("/gibt/es/nicht"))
    assert_equal 0, ergebnis[:dateien]
  end
end
