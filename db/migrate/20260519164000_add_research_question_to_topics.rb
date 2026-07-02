# #155 Phase 5b: Recherche-Topics tragen die zugrundeliegende Frage.
# Optional — normale Topics haben sie nicht, Recherchen schon.
class AddResearchQuestionToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :research_question, :text
  end
end
