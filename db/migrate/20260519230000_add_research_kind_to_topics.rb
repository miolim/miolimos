# #155 Schritt 3: Recherche-Typ am Topic. Bestimmt, welche Synthese-
# Struktur-Vorlage instanziiert wird. Nullable — normale Topics tragen
# keinen research_kind.
class AddResearchKindToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :research_kind, :string
  end
end
