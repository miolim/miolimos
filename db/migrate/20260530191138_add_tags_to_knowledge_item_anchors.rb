# #387 Phase B (Hans, 2026-05-30): Highlights bekommen Tags ueber
# Inline-Syntax (`==color|text==^anchor#tag1#tag2`). Tags landen hier.
class AddTagsToKnowledgeItemAnchors < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_item_anchors, :tags, :string, array: true, default: []
  end
end
