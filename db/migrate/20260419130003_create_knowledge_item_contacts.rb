class CreateKnowledgeItemContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_item_contacts do |t|
      t.string :knowledge_item_uuid, null: false
      t.references :contact, null: false, foreign_key: true

      t.timestamps
    end

    add_foreign_key :knowledge_item_contacts, :knowledge_items,
      column: :knowledge_item_uuid, primary_key: :uuid

    add_index :knowledge_item_contacts, :knowledge_item_uuid
    add_index :knowledge_item_contacts, [:knowledge_item_uuid, :contact_id],
      unique: true, name: "index_kic_on_item_and_contact"
  end
end
