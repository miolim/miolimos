# #239 Phase D: explizites Vokabular fuer typed Wikilink-Beziehungen.
# Label-Spalte auf Relations bleibt freitext — Typen sind ein Overlay,
# das Inverse-Name liefert (Source sagt „loest aus", Target sieht
# „wird ausgeloest von") und in den Einstellungen kuratierbar ist.
# Lookup ueber LOWER(name) = LOWER(label), keine FK.
class CreateRelationTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :relation_types do |t|
      t.string :name,         null: false
      t.string :inverse_name
      t.text   :description
      t.timestamps
    end
    add_index :relation_types, "LOWER(name)", unique: true, name: "index_relation_types_on_lower_name"
  end
end
