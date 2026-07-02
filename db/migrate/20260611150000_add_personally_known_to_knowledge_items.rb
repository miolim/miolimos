# #608: manuelle Bekanntheits-Markierung an Person-KIs. Reines DB-Feld
# (kein Frontmatter — Konvention #544: neue per-KI-Daten dürfen pure DB
# sein). Das automatische Pendant (Kommunikation vorhanden) wird zur
# Laufzeit aus communication_mentions abgeleitet.
class AddPersonallyKnownToKnowledgeItems < ActiveRecord::Migration[8.0]
  def change
    add_column :knowledge_items, :personally_known, :boolean, default: false, null: false
  end
end
