class KiTemplate < ApplicationRecord
  validates :name, presence: true
  validates :item_type, presence: true

  # Picker-Suggest: nach Name/Titel filtern.
  scope :search, ->(q) {
    pattern = "%#{q.to_s.strip}%"
    where("name ILIKE ? OR title ILIKE ?", pattern, pattern)
  }
end
