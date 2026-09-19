require "test_helper"

# #1677 (aus immoOS #1658 übernommen) Stufe 3: Die Erklärungen des Programms wandern über das
# Repository von Instanz zu Instanz — ohne dass ein Import einen vor Ort
# geschriebenen Text überfährt.
class HelpCardSyncTest < ActiveSupport::TestCase
  setup do
    @vorher = HelpCardSync.verzeichnis
    @verzeichnis = Rails.root.join("tmp/test_help_#{SecureRandom.hex(4)}")
    HelpCardSync.verzeichnis = @verzeichnis
  end

  teardown do
    FileUtils.rm_rf(@verzeichnis)
    HelpCardSync.verzeichnis = @vorher
  end

  def datei(key) = @verzeichnis.join(HelpCardSync.dateiname(key))

  test "Export schreibt je Erklärung eine Datei" do
    HelpCard.create!(key: "task", program_body: "Zur Aufgabe", user_body: "Unsere Notiz")
    HelpCard.create!(key: "list:persons", program_body: "Zur Personenliste")
    # Ohne Erklärung keine Datei — eine reine Notiz gehört ihrer Instanz.
    HelpCard.create!(key: "topic", user_body: "Nur intern")

    bericht = HelpCardSync.export!
    assert_equal %w[list:persons task], bericht[:geschrieben].sort
    assert_equal "Zur Aufgabe\n", datei("task").read
    assert_equal "Zur Personenliste\n", datei("list:persons").read
    assert_not datei("topic").exist?
    # Der Notiz-Text bleibt in der Datenbank und landet in keiner Datei.
    assert_not_includes datei("task").read, "Unsere Notiz"
  end

  test "Export entfernt die Datei einer gelöschten Erklärung" do
    karte = HelpCard.create!(key: "task", program_body: "Zur Aufgabe")
    HelpCardSync.export!
    assert datei("task").exist?

    karte.update!(program_body: nil, user_body: "bleibt")
    bericht = HelpCardSync.export!
    assert_equal ["task"], bericht[:entfernt]
    assert_not datei("task").exist?
  end

  test "Import legt fehlende Erklärungen an" do
    FileUtils.mkdir_p(@verzeichnis)
    datei("task").write("Zur Aufgabe\n")

    bericht = HelpCardSync.import!
    assert_equal ["task"], bericht[:angelegt]
    assert_equal "Zur Aufgabe", HelpCard.find_by(key: "task").program_body
  end

  test "Import lässt die Notiz der Instanz unberührt" do
    HelpCard.create!(key: "task", user_body: "Unsere Notiz")
    FileUtils.mkdir_p(@verzeichnis)
    datei("task").write("Zur Aufgabe\n")

    HelpCardSync.import!
    karte = HelpCard.find_by(key: "task")
    assert_equal "Unsere Notiz", karte.user_body
    assert_equal "Zur Aufgabe", karte.program_body
  end

  test "Import aktualisiert einen unveränderten Text" do
    HelpCard.create!(key: "task", program_body: "Alt")
    HelpCardSync.export! # setzt den Abgleichsstand
    datei("task").write("Neu aus dem Repository\n")

    bericht = HelpCardSync.import!
    assert_equal ["task"], bericht[:aktualisiert]
    assert_equal "Neu aus dem Repository", HelpCard.find_by(key: "task").program_body
  end

  # Der Kern von Stufe 3: Ein Deploy darf nicht wegnehmen, was jemand hier
  # gerade geschrieben hat.
  test "Import überschreibt einen vor Ort geänderten Text NICHT" do
    HelpCard.create!(key: "task", program_body: "Alt")
    HelpCardSync.export!
    HelpCard.find_by(key: "task").update!(program_body: "Vor Ort geändert")
    datei("task").write("Aus dem Repository\n")

    bericht = HelpCardSync.import!
    assert_equal ["task"], bericht[:uebersprungen]
    assert_equal "Vor Ort geändert", HelpCard.find_by(key: "task").program_body
  end

  # Die Datei endet mit Zeilenumbruch, das Textfeld nicht. Dieser Unterschied
  # darf nicht als Änderung vor Ort gelten — sonst kommt die Datei nie wieder
  # durch, und der Deploy meldet nur noch, dass er nichts tut.
  test "ein Zeilenumbruch am Ende ist keine Aenderung vor Ort" do
    karte = HelpCard.create!(key: "task", program_body: "Zur Aufgabe\n")
    HelpCardSync.export!
    datei("task").write("Neu aus dem Repository\n")

    bericht = HelpCardSync.import!
    assert_empty bericht[:uebersprungen]
    assert_equal ["task"], bericht[:aktualisiert]
    assert_equal "Neu aus dem Repository", karte.reload.program_body
  end

  test "Import ist beim zweiten Lauf wirkungslos" do
    FileUtils.mkdir_p(@verzeichnis)
    datei("task").write("Zur Aufgabe\n")
    HelpCardSync.import!

    bericht = HelpCardSync.import!
    assert_equal ["task"], bericht[:unveraendert]
    assert_empty bericht[:aktualisiert]
  end

  test "Export und Import vertragen Reiter-Schlüssel" do
    HelpCard.create!(key: "property.settlement", program_body: "Zur Abrechnung")
    HelpCardSync.export!
    assert_equal "property.settlement.md", HelpCardSync.dateiname("property.settlement")

    HelpCard.delete_all
    HelpCardSync.import!
    assert_equal "Zur Abrechnung", HelpCard.find_by(key: "property.settlement")&.program_body
  end

  # Die mitgelieferten Erklärungen sind Teil des Programms: Eine Datei, deren
  # Name kein gültiger Schlüssel ist, käme nie in der Oberfläche an — und zwar
  # stillschweigend.
  test "jede mitgelieferte Erklärung traegt einen gueltigen Schluessel" do
    dateien = Dir.glob(Rails.root.join("db/help/*.md"))
    assert_operator dateien.size, :>, 0, "db/help ist leer"
    dateien.each do |pfad|
      key = HelpCardSync.schluessel_aus_dateiname(pfad)
      assert_match HelpCard::KEY_RE, key, "#{File.basename(pfad)} ergibt keinen gueltigen Schluessel"
      assert File.read(pfad).strip.present?, "#{File.basename(pfad)} ist leer"
    end
  end

  # #1666 (Hans): „Wie bekommst Du mit, dass ein Hilfetext im Interface
  # angepasst wurde?" — Die Abfrage muss die zwei Fälle trennen, die jemand
  # anfassen muss, von den zwei, die sich beim nächsten Import von selbst
  # erledigen. Sonst meldet sie dauernd etwas und wird überlesen.
  test "Rueckstand meldet einen vor Ort geaenderten Text" do
    HelpCard.create!(key: "task", program_body: "Alt")
    HelpCardSync.export!
    HelpCard.find_by(key: "task").update!(program_body: "Vor Ort geändert")

    b = HelpCardSync.rueckstand
    assert_equal ["task"], b[:vor_ort_geaendert]
    assert_empty b[:programm_neuer]
    assert HelpCardSync.rueckstand?
  end

  test "Rueckstand meldet eine nie exportierte Erklaerung" do
    FileUtils.mkdir_p(@verzeichnis)
    HelpCard.create!(key: "task", program_body: "Nur hier geschrieben")

    b = HelpCardSync.rueckstand
    assert_equal ["task"], b[:nur_datenbank]
    assert HelpCardSync.rueckstand?
  end

  test "Rueckstand haelt einen neueren Programmtext NICHT fuer Handarbeit" do
    HelpCard.create!(key: "task", program_body: "Alt")
    HelpCardSync.export!
    datei("task").write("Neu aus dem Repository\n")

    b = HelpCardSync.rueckstand
    assert_equal ["task"], b[:programm_neuer]
    assert_empty b[:vor_ort_geaendert]
    assert_not HelpCardSync.rueckstand?, "das zieht der nächste Import von allein nach"
  end

  test "Rueckstand meldet eine Datei ohne Karte als kommend" do
    FileUtils.mkdir_p(@verzeichnis)
    datei("task").write("Aus dem Repository\n")

    b = HelpCardSync.rueckstand
    assert_equal ["task"], b[:nur_repository]
    assert_not HelpCardSync.rueckstand?
  end

  test "Rueckstand ist leer, wenn Datenbank und Dateien einig sind" do
    HelpCard.create!(key: "task", program_body: "Zur Aufgabe")
    HelpCardSync.export!

    b = HelpCardSync.rueckstand
    assert_equal({ vor_ort_geaendert: [], nur_datenbank: [], programm_neuer: [], nur_repository: [] }, b)
    assert_not HelpCardSync.rueckstand?
  end

  test "eine Datei mit unbrauchbarem Namen wird übergangen" do
    FileUtils.mkdir_p(@verzeichnis)
    @verzeichnis.join("LIESMICH.md").write("kein Schlüssel")
    @verzeichnis.join("leer.md").write("   \n")

    bericht = HelpCardSync.import!
    assert_empty bericht[:angelegt]
    assert_equal 0, HelpCard.count
  end
end
