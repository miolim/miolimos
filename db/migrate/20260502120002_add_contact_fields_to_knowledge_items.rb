class AddContactFieldsToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    # Person/Org-spezifische Felder, die früher auf der Contact-Tabelle
    # lagen. Optional auf KI — nur Person/Org füllen sie.
    add_column :knowledge_items, :email,   :string
    add_column :knowledge_items, :phone,   :string
    add_column :knowledge_items, :website, :string

    add_index :knowledge_items, "lower(email)", name: "idx_kis_lower_email"
  end
end
