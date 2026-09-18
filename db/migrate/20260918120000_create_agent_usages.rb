# #1660 (Hans): „Ich hätte gern in den Einstellungen eine Gesamtübersicht,
# sowohl zeitlich als auch nach Aufgabe gegliedert und dann jeweils Modell,
# Eingabe, Ausgabe, Cache mit jeweiligen Kosten und dann Gesamtkosten."
#
# Die Rohdaten liegen in den Sitzungsprotokollen der Agenten (JSONL, eine
# Zeile je Nachricht, mit Token-Verbrauch je Antwort). Hier liegt die
# VERDICHTUNG: eine Zeile je Tag × Projekt × Aufgabe × Modell. Der Import
# schreibt sie idempotent fort (gleicher Schlüssel = ersetzen), damit ein
# erneuter Lauf nichts doppelt.
class CreateAgentUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_usages do |t|
      t.date    :tag,     null: false
      t.string  :projekt, null: false          # Arbeitsverzeichnis der Sitzung
      t.string  :aufgabe                       # Aufgabennummer aus der Auslöser-Zeile, nil = ohne
      t.string  :model,   null: false
      t.integer :antworten,              null: false, default: 0
      t.bigint  :input_tokens,           null: false, default: 0
      t.bigint  :cache_creation_tokens,  null: false, default: 0
      t.bigint  :cache_read_tokens,      null: false, default: 0
      t.bigint  :output_tokens,          null: false, default: 0

      t.timestamps
    end

    add_index :agent_usages, [:tag, :projekt, :aufgabe, :model], unique: true,
              name: "index_agent_usages_on_schluessel"
    add_index :agent_usages, :aufgabe
  end
end
