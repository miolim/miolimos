class AddInboxItemToKnowledgeItemsAndTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :knowledge_items, :inbox_item, foreign_key: true,
                                                  index: true, type: :bigint
    add_reference :tasks,           :inbox_item, foreign_key: true,
                                                  index: true, type: :bigint
  end
end
