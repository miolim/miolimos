class AddParentOrgToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :parent_org_uuid, :string
    add_index  :knowledge_items, :parent_org_uuid
  end
end
