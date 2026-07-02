class TaskMention < ApplicationRecord
  belongs_to :task
  belongs_to :mentioned,
    class_name: "KnowledgeItem",
    foreign_key: :mentioned_uuid, primary_key: :uuid

  validates :task_id, uniqueness: { scope: :mentioned_uuid }
end
