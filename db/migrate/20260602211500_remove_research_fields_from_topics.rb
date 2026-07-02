class RemoveResearchFieldsFromTopics < ActiveRecord::Migration[8.0]
  # #472 (Hans, 2026-06-02): research_question + research_kind aus dem
  # Datenmodell entfernen. Recherche-Topics laufen jetzt ueber Vorlagen/
  # Tags (#471), Synthesen ueber die Synthese-KI-Vorlagen (Schritt 2a)
  # statt research_kind-gesteuert. UI-Felder + create_synthesis +
  # SynthesisTemplate sind bereits raus. Nutzung in Prod war ~null
  # (0 research_question, 1 research_kind).
  def up
    remove_column :topics, :research_question
    remove_column :topics, :research_kind
  end

  def down
    add_column :topics, :research_question, :text
    add_column :topics, :research_kind, :string
  end
end
