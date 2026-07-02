# #155 Phase 5a: Ebene-Achse fuer das RelationType-Vokabular. Hans'
# Verbindungstypologie (inhaltlich/organisatorisch/sozial/politisch)
# laesst sich pro Typ hinterlegen — Backlinks-View und Statistik
# koennen dann nach Ebene gruppieren oder farblich markieren.
class AddEbeneToRelationTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :relation_types, :ebene, :string
    add_index  :relation_types, :ebene
  end
end
