# immoOS #1658 Stufe 3 (Hans): „Dann bitte weiter machen mit Stufe 2 und 3."
#
# Die Erklärungen des Programms sind Teil des Programms — sie gehören ins
# Repository, nicht nur in die Datenbank einer Instanz. Geschrieben werden sie
# dort, wo gearbeitet wird; gelesen werden sollen sie überall.
#
#   bin/rails help:export   Datenbank → db/help/<schluessel>.md   (danach committen)
#   bin/rails help:import   db/help/*.md → Datenbank              (läuft im Deploy)
#
# Nur `program_body` wandert. „Unsere Notiz" (`user_body`) gehört der Instanz,
# die sie geschrieben hat, und bleibt liegen.
#
# Schutz gegen Überschreiben: `program_digest` hält fest, wie der Text beim
# letzten Abgleich aussah. Weicht der Text in der Datenbank davon ab, hat ihn
# jemand vor Ort geändert — dann lässt der Import ihn stehen und meldet es.
module HelpCardSync
  ENDUNG = ".md"

  # Wo die Dateien liegen. Als Schalter, damit der Test in einem eigenen
  # Verzeichnis arbeiten kann statt im echten db/help.
  mattr_accessor :verzeichnis, default: Rails.root.join("db/help")

  # Vor dem Vergleich normalisiert: Die Datei endet immer mit Zeilenumbruch,
  # das Textfeld nicht. Ohne strip hielte der Abgleich diesen Unterschied für
  # eine Änderung vor Ort und ließe die Datei nie mehr durch (so geschehen
  # beim ersten Import von property).
  def self.digest(text) = Digest::SHA256.hexdigest(text.to_s.strip)

  # Der Schlüssel enthält ":" (list:persons). Im Dateinamen steht dafür "-";
  # Schlüssel selbst enthalten nie "-", der Rückweg ist also eindeutig.
  def self.dateiname(key) = "#{key.tr(":", "-")}#{ENDUNG}"

  def self.schluessel_aus_dateiname(name) = File.basename(name, ENDUNG).tr("-", ":")

  # ── Datenbank → Repository ───────────────────────────────────────────
  def self.export!
    FileUtils.mkdir_p(verzeichnis)
    bericht = { geschrieben: [], entfernt: [] }
    aktuell = {}

    HelpCard.where.not(program_body: [nil, ""]).order(:key).each do |karte|
      aktuell[dateiname(karte.key)] = karte
      pfad = verzeichnis.join(dateiname(karte.key))
      inhalt = karte.program_body.to_s
      inhalt += "\n" unless inhalt.end_with?("\n")
      bericht[:geschrieben] << karte.key unless pfad.exist? && pfad.read == inhalt
      pfad.write(inhalt)
      # Der Text ist jetzt abgeglichen — ein Import danach ändert nichts mehr.
      karte.update_columns(program_digest: digest(karte.program_body))
    end

    # Eine gelöschte Erklärung muss auch die Datei verlieren, sonst kommt sie
    # beim nächsten Import zurück.
    Dir.glob(verzeichnis.join("*#{ENDUNG}")).each do |pfad|
      name = File.basename(pfad)
      next if aktuell.key?(name)

      File.delete(pfad)
      bericht[:entfernt] << schluessel_aus_dateiname(name)
    end
    bericht
  end

  # ── Repository → Datenbank ───────────────────────────────────────────
  def self.import!
    bericht = { angelegt: [], aktualisiert: [], unveraendert: [], uebersprungen: [] }
    return bericht unless Dir.exist?(verzeichnis)

    Dir.glob(verzeichnis.join("*#{ENDUNG}")).sort.each do |pfad|
      key = schluessel_aus_dateiname(pfad)
      text = File.read(pfad).strip
      next if text.blank?
      # Eine Datei, die kein gültiger Schlüssel ist, wird nicht stillschweigend
      # zu einer Karte — sie ist ein Versehen.
      next unless HelpCard::KEY_RE.match?(key)

      karte = HelpCard.fuer(key)
      if karte.new_record?
        karte.update!(program_body: text, program_digest: digest(text))
        bericht[:angelegt] << key
      elsif karte.program_body.to_s.strip == text
        # Schon gleich — nur den Abgleichsstand nachziehen.
        karte.update_columns(program_digest: digest(text))
        bericht[:unveraendert] << key
      elsif karte.program_body.blank? || digest(karte.program_body) == karte.program_digest
        karte.update!(program_body: text, program_digest: digest(text))
        bericht[:aktualisiert] << key
      else
        # Vor Ort geändert: Der lokale Text gewinnt. Wer ihn behalten will,
        # exportiert ihn und committet die Datei.
        bericht[:uebersprungen] << key
      end
    end
    bericht
  end

  # ── Was steht aus? (#1666) ───────────────────────────────────────────
  #
  # Hans' Frage war: „Wie bekommst Du mit, dass ein Hilfetext im Interface
  # angepasst wurde und deshalb auch im Code nachgezogen werden muss?" Bis
  # hierher gar nicht — der Import meldet es nur im Deploy-Protokoll, also
  # genau dann, wenn niemand hinsieht. Diese Abfrage fragt es aktiv ab, ohne
  # etwas zu ändern; sie läuft zu Beginn jedes Inbox-Laufs auf beiden
  # Instanzen.
  #
  #   :vor_ort_geaendert  Datenbank ≠ Datei UND der Text weicht vom letzten
  #                       Abgleich ab → jemand hat ihn im Programm bearbeitet.
  #                       Handlung: help:export, Datei committen, ausrollen.
  #   :nur_datenbank      Erklärung existiert, aber keine Datei → wurde nie
  #                       exportiert, andere Instanzen kennen sie nicht.
  #   :programm_neuer     Datei ≠ Datenbank, aber der lokale Text ist
  #                       unverändert seit dem letzten Abgleich → der nächste
  #                       Import zieht ihn nach. Keine Handlung nötig.
  #   :nur_repository     Datei ohne Karte in dieser Datenbank → kommt mit dem
  #                       nächsten Import. Keine Handlung nötig.
  def self.rueckstand
    bericht = { vor_ort_geaendert: [], nur_datenbank: [], programm_neuer: [], nur_repository: [] }
    dateien = Dir.exist?(verzeichnis) ? Dir.glob(verzeichnis.join("*#{ENDUNG}")).sort : []
    gesehen = []

    HelpCard.where.not(program_body: [nil, ""]).order(:key).each do |karte|
      gesehen << karte.key
      pfad = verzeichnis.join(dateiname(karte.key))
      unless pfad.exist?
        bericht[:nur_datenbank] << karte.key
        next
      end
      next if pfad.read.strip == karte.program_body.to_s.strip

      if digest(karte.program_body) == karte.program_digest
        bericht[:programm_neuer] << karte.key
      else
        bericht[:vor_ort_geaendert] << karte.key
      end
    end

    dateien.each do |pfad|
      key = schluessel_aus_dateiname(pfad)
      bericht[:nur_repository] << key unless gesehen.include?(key)
    end
    bericht
  end

  # Nur die Fälle, die jemand anfassen muss.
  def self.rueckstand?
    b = rueckstand
    b[:vor_ort_geaendert].any? || b[:nur_datenbank].any?
  end
end
