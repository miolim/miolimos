# #1677 (aus immoOS #1658 Stufe 3 übernommen): Programm-Hilfen zwischen den Instanzen abgleichen.
# Siehe HelpCardSync — dort steht, warum lokale Änderungen gewinnen.
namespace :help do
  desc "Programm-Hilfen aus der Datenbank nach db/help/ schreiben (danach committen)"
  task export: :environment do
    bericht = HelpCardSync.export!
    puts "  geschrieben: #{bericht[:geschrieben].size} (#{bericht[:geschrieben].join(', ')})"
    puts "  entfernt:    #{bericht[:entfernt].size} (#{bericht[:entfernt].join(', ')})" if bericht[:entfernt].any?
  end

  desc "Programm-Hilfen aus db/help/ in die Datenbank laden (lokal Geändertes bleibt stehen)"
  task import: :environment do
    bericht = HelpCardSync.import!
    puts "  neu: #{bericht[:angelegt].size} · aktualisiert: #{bericht[:aktualisiert].size} · " \
         "unverändert: #{bericht[:unveraendert].size}"
    if bericht[:uebersprungen].any?
      puts "  vor Ort geändert, NICHT überschrieben: #{bericht[:uebersprungen].join(', ')}"
      puts "  → wer diesen Stand behalten will: bin/rails help:export und die Datei committen"
    end
  end

  # #1666 (Hans): „Wie bekommst Du mit, dass ein Hilfetext im Interface
  # angepasst wurde?" — Diese Abfrage ändert nichts und beantwortet genau das.
  # Rückgabe 1, wenn etwas nachzuziehen ist; damit taugt sie als Wächter im
  # Skript und als erster Handgriff im Inbox-Lauf.
  desc "Zeigt, welche Hilfetexte zwischen Datenbank und db/help/ auseinanderlaufen"
  task rueckstand: :environment do
    b = HelpCardSync.rueckstand
    instanz = ENV.fetch("MIOLIMOS_HOST", "(unbenannte Instanz)")

    if b[:vor_ort_geaendert].any?
      puts "  #{instanz}: VOR ORT GEÄNDERT (#{b[:vor_ort_geaendert].size}) — #{b[:vor_ort_geaendert].join(', ')}"
      puts "  → bin/rails help:export, Datei ansehen, committen, ausrollen"
    end
    if b[:nur_datenbank].any?
      puts "  #{instanz}: NUR IN DER DATENBANK (#{b[:nur_datenbank].size}) — #{b[:nur_datenbank].join(', ')}"
      puts "  → nie exportiert; andere Instanzen kennen diese Erklärung nicht"
    end
    puts "  #{instanz}: kommt mit dem nächsten Import: #{(b[:programm_neuer] + b[:nur_repository]).join(', ')}" \
      if (b[:programm_neuer] + b[:nur_repository]).any?

    if b[:vor_ort_geaendert].empty? && b[:nur_datenbank].empty?
      puts "  #{instanz}: kein Rückstand — Datenbank und db/help/ sind einig."
    else
      exit 1
    end
  end
end
