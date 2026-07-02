# #768 (Hans): explizite Selbst-Identität "Das bin ich" — verknüpft einen
# (Human-)Actor mit seiner Person-KI. Ersetzt die Postfach-Überschneidungs-
# Heuristik zur Bestimmung der eigenen Adressen für den Mail-Sync-Filter.
class AddPersonKiUuidToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :person_ki_uuid, :string
    add_index  :actors, :person_ki_uuid
  end
end
