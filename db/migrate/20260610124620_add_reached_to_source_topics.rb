# #575: Relevanz-Markierung an Quelle↔Thema in zwei Dimensionen aufgliedern
# (Hans, 2026-06-10): relevant/irrelevant (inhaltliches Urteil) ist
# unabhängig von erreicht/nicht-erreicht (Zugriff). Der bisherige dritte
# relevance-Wert "unreached" (= vermutlich relevant, aber nicht erreicht)
# wird zu relevance=relevant + reached=false migriert.
class AddReachedToSourceTopics < ActiveRecord::Migration[8.1]
  def up
    add_column :source_topics, :reached, :boolean, null: false, default: true
    execute <<~SQL
      UPDATE source_topics
         SET reached = FALSE, relevance = 'relevant'
       WHERE relevance = 'unreached'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE source_topics
         SET relevance = 'unreached'
       WHERE reached = FALSE
    SQL
    remove_column :source_topics, :reached
  end
end
