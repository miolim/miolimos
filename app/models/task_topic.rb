class TaskTopic < ApplicationRecord
  belongs_to :task
  belongs_to :topic

  validates :task_id, uniqueness: { scope: :topic_id }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Eine Topic hat maximal einen Next-Step. DB-seitig über partial unique
  # index abgesichert; Validation ist Nutzer-freundlicher Fehler-Text.
  validate :only_one_next_step_per_topic, if: :next_step?
  validate :next_step_must_be_open_task,  if: :next_step?

  scope :next_step, -> { where(next_step: true) }

  private

  def only_one_next_step_per_topic
    existing = TaskTopic.where(topic_id: topic_id, next_step: true).where.not(id: id)
    return unless existing.exists?
    errors.add(:next_step, "ist für dieses Thema bereits an eine andere Aufgabe vergeben")
  end

  def next_step_must_be_open_task
    return if task&.open?
    errors.add(:next_step, "kann nur eine offene Aufgabe sein")
  end
end
