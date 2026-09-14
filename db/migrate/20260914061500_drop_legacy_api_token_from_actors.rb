# #1499 Punkt 1 (Hans, Rotation 14.09.2026): „OK, dann bitte bauen."
#
# Jeder Agent hat jetzt benannte Token (api_tokens). Das alte Einzel-Token an
# der Actor-Spalte stammt aus der Zeit vor #1052; Kopien seines Klartexts aus
# dieser Zeit liessen sich nicht mehr vollstaendig einsammeln. Hashen machte
# sie nicht wertlos, nur das Entfernen tut es.
#
# `down` legt die Spalten leer wieder an: Die Pruefwerte kommen nicht zurueck,
# und das ist Absicht — ein Rueckweg, der die alten Token wieder gueltig
# machte, waere genau das, was diese Migration beenden soll.
class DropLegacyApiTokenFromActors < ActiveRecord::Migration[8.1]
  def up
    remove_index  :actors, :api_token_digest, if_exists: true
    remove_column :actors, :api_token_digest
    remove_column :actors, :api_token_last_used_at
  end

  def down
    add_column :actors, :api_token_digest, :string
    add_column :actors, :api_token_last_used_at, :datetime
    add_index  :actors, :api_token_digest, unique: true
  end
end
