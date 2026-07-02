# Generische Key/Value-Settings. Aktuell genutzt für das editierbare
# Chat-Import-Prompt-Template; erweiterbar für andere Konfig-Werte,
# die über ENV/Konstanten hinausgehen.
class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key, default: nil)
    where(key: key.to_s).pick(:value) || default
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key.to_s)
    record.value = value.to_s
    record.save!
    record
  end

  # #768 (Hans): Mail-Sync-Policy. true (Default) = internen Team-Verkehr
  # ausschließen (alle verbundenen Konten + deren Selbst-KIs gelten als
  # „intern"; importiert wird nur mit externem Kontakt). false = nur der
  # jeweilige Konto-Inhaber gilt als „ich" (interner Team-Verkehr wird
  # importiert).
  SYNC_EXCLUDE_INTERNAL_KEY = "sync_exclude_internal_team".freeze

  def self.sync_exclude_internal_team?
    get(SYNC_EXCLUDE_INTERNAL_KEY, default: "true") != "false"
  end
end
