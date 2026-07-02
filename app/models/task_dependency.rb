class TaskDependency < ApplicationRecord
  belongs_to :predecessor, class_name: "Task"
  belongs_to :successor, class_name: "Task"

  enum :dependency_type, {
    finish_to_start:  0,
    start_to_start:   1,
    finish_to_finish: 2
  }, default: :finish_to_start

  validates :predecessor_id, uniqueness: { scope: :successor_id }
  validate  :no_self_reference
  validate  :no_cycle

  private

  def no_self_reference
    return unless predecessor_id.present? && predecessor_id == successor_id
    errors.add(:successor_id, "must differ from predecessor")
  end

  def no_cycle
    return unless predecessor_id.present? && successor_id.present?
    return if successor_id == predecessor_id
    if reachable?(from: successor_id, to: predecessor_id)
      errors.add(:base, "would introduce a circular dependency")
    end
  end

  def reachable?(from:, to:, visited: Set.new)
    return false unless visited.add?(from)
    next_ids = TaskDependency.where(predecessor_id: from).pluck(:successor_id)
    return true if next_ids.include?(to)
    next_ids.any? { |nid| reachable?(from: nid, to: to, visited: visited) }
  end
end
