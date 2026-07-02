class AuditLog < ApplicationRecord
  self.record_timestamps = false

  belongs_to :actor
  belongs_to :auditable, polymorphic: true

  validates :action, presence: true

  before_create :stamp_created_at

  def readonly?
    persisted?
  end

  private

  def stamp_created_at
    self.created_at ||= Time.current
  end
end
