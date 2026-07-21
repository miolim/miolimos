# #1090 (Hans): Geschlecht + Anrede an der Person. `gender` ist ein
# Katalogwert (Salutations::GENDERS), `salutation` ein Freitext-Override
# der Briefanrede — beides fakultativ.
class AddGenderAndSalutationToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :gender, :string, null: true
    add_column :knowledge_items, :salutation, :string, null: true
  end
end
