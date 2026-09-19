# #1677 (aus immoOS #1658 übernommen; Hans dort): „Ich möchte nach und nach Hilfe-Cards ergänzen, die das
# Programm erläutern. … Die Hilfe-Card hat zwei Bereiche: Oben ein Bereich, den
# der Nutzer selbst bearbeiten kann; unten der Bereich, der vom Programm
# geliefert wird."
#
# Eine schmale eigene Tabelle statt zweier Wissens-Einträge je Card: Der
# Schlüssel ist die Karten-Art (`property`) bzw. Karten-Art + Reiter
# (`property.settlement`), und die beiden Bereiche unterscheiden sich nur im
# Schreibrecht. Dasselbe Muster wie OwnerColor (#839) — eine kleine Zuordnung
# neben dem KI-Kern, statt ihn zu belasten.
#
# Der Export ins Code-Repo (Stufe 3, Verteilung an weitere Mandanten) ist damit
# eine Zeile je Schlüssel; gebaut wird er, wenn der zweite Mandant kommt.
class HilfeKarten < ActiveRecord::Migration[8.1]
  def change
    create_table :help_cards do |t|
      # Karten-Art aus lib/blade_stack_routes.js, optional + "." + Reitername.
      t.string :key, null: false
      # Oben: frei für alle, die das Programm bedienen.
      t.text :user_body
      # Unten: die Erklärung des Programms — nur für Administratoren änderbar.
      t.text :program_body
      t.timestamps
    end
    add_index :help_cards, :key, unique: true
  end
end
