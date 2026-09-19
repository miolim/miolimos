require "test_helper"

# #1677 (aus immoOS #1654 übernommen; Hans dort): „Wenn ich im Suchfeld in der
# Topbar nach WEG suche, gibt es keine Treffer bei den Personen."
#
# Ursache ist die deutsche Volltext-Konfiguration von PostgreSQL: „weg" ist dort
# ein STOPPWORT — wie „Am", „Bei", „Zum", „Vor". Nachzumessen in einer Zeile:
#
#   SELECT to_tsvector('german', 'WEG Am Speicher 11');  → 'speich':3 '11':4
#   SELECT websearch_to_tsquery('german', 'WEG');        → (leer)
#
# Eine leere Anfrage trifft nichts — in keiner Sektion. Die Suche fällt deshalb
# genau in diesem Fall auf einen Textvergleich zurück.
class SearchStoppwort1654Test < ActiveSupport::TestCase
  setup do
    @hans = create_human(email: "sw-#{SecureRandom.hex(3)}@t.local")
    @weg = kontakt("WEG Am Speicher 11")
    @andere = kontakt("Zuria Immobilien GmbH")
  end

  def kontakt(title)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title, item_type: :organization,
                          creator_id: @hans.id, file_path: "kb/#{SecureRandom.hex(4)}.md",
                          content_hash: SecureRandom.hex(8))
  end

  def q(text) = SearchQuery.new(text, actor: @hans)

  # Die Vorbedingung — ohne sie prüfte der Test an der Ursache vorbei.
  test "die deutsche Konfiguration wirft das Wort weg als Stoppwort weg" do
    leer = ActiveRecord::Base.connection.select_value(
      "SELECT websearch_to_tsquery('german', 'WEG')::text = ''"
    )
    assert leer, "Vorbedingung: die Volltext-Anfrage fuer WEG ist leer"
    assert q("WEG").nur_stoppwoerter?
  end

  test "#1654: die Suche nach WEG findet die Gemeinschaft" do
    treffer = q("WEG").records(:contacts, limit: 20)
    assert_includes treffer.map(&:uuid), @weg.uuid
    assert_not_includes treffer.map(&:uuid), @andere.uuid
  end

  test "#1654: auch andere Funktionswörter im Namen finden ihr Ziel" do
    haus = kontakt("Hausverwaltung Am Markt")
    assert_includes q("Am Markt").records(:contacts, limit: 20).map(&:uuid), haus.uuid
  end

  test "#1654: Aufgaben fallen genauso zurück" do
    aufgabe = Task.create!(creator: @hans, title: "WEG-Abrechnung prüfen", status: :open)
    assert_includes q("WEG").records(:tasks, limit: 20).map(&:id), aufgabe.id
  end

  # Die Gegenprobe: Eine normale Anfrage läuft weiter über den Volltext — sonst
  # hätten wir die Suche insgesamt auf Textvergleich umgestellt.
  test "eine gewöhnliche Anfrage bleibt Volltextsuche" do
    assert_not q("Zuria").nur_stoppwoerter?
    assert_includes q("Zuria").records(:contacts, limit: 20).map(&:uuid), @andere.uuid
    # Stammformen: „Immobilien" findet die GmbH über den Volltext-Index.
    assert_includes q("Immobilien").records(:contacts, limit: 20).map(&:uuid), @andere.uuid
  end

  # #1677: Beim Übertragen gefunden — bei uns UND im Fork. Der Suchtext stand
  # (sauber gequotet) im SQL-TEXT, und die Bedingung trug daneben benannte
  # Bindewerte (`:cp`, `:l`). Rails hält dann auch ein `:morgen` IM Suchtext für
  # einen Platzhalter: „missing value for :morgen" — die Suche endete in einer
  # Fehlerseite. Jede Sektion muss solche Eingaben aushalten.
  test "Suchtext mit Doppelpunkt, Fragezeichen oder Prozent sprengt keine Sektion" do
    aufgabe = Task.create!(creator: @hans, title: "Termin :morgen klären", status: :open)
    ["termin :morgen", "wer? was?", "10:30 uhr", "100% sicher", "bei :der", "o'brien :x"].each do |text|
      suche = q(text)
      SearchQuery::SECTIONS.each do |sektion|
        begin
          suche.count(sektion)
        rescue => fehler
          flunk "#{text.inspect} sprengt die Sektion #{sektion}: #{fehler.class}: #{fehler.message[0, 120]}"
        end
      end
    end
    assert_includes q("termin :morgen").records(:tasks, limit: 20).map(&:id), aufgabe.id
  end
end