class TaskSource < ApplicationRecord
  belongs_to :task
  belongs_to :source

  validates :task_id, uniqueness: { scope: :source_id }
end
