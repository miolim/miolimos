# #1499 (Hans): "Wie lange gelten die Token und lassen sie sich einzeln
# zurueckziehen?" -- bisher: unbegrenzt und nein. Jeder Agent hatte GENAU EIN
# Token in einer Spalte an sich selbst; rotieren traf alles gleichzeitig, wo
# dieser Agent lief.
#
# Ein Token ist jetzt ein eigener Gegenstand mit Namen, Ablauf, letzter
# Benutzung und eigenem Rueckzug. Damit wird beantwortbar, was vorher nicht
# einmal fragbar war: Welches Token wird ueberhaupt noch benutzt? Von wann ist
# es? Kann ich genau dieses eine abschalten, ohne die anderen zu stoeren?
#
# Die alte Spalte `actors.api_token_digest` bleibt vorerst: Alle laufenden
# Agenten senden ihr altes Token, und ein Umstieg, der sie alle gleichzeitig
# aussperrt, waere das Gegenteil von Sicherheit. Sie faellt, wenn die Tokens
# rotiert sind (#1499 Punkt 1).
class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :actor, null: false, foreign_key: true
      t.string   :name,         null: false
      t.string   :token_digest, null: false
      t.datetime :expires_at
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :api_tokens, :token_digest, unique: true
    add_index :api_tokens, [:actor_id, :revoked_at]

    # #1499 Punkt 2: Auch fuer das ALTE Token soll sichtbar werden, wann es
    # zuletzt benutzt wurde -- sonst bleibt bis zur Rotation blind, was gerade
    # der interessanteste Fall ist.
    add_column :actors, :api_token_last_used_at, :datetime
  end
end
