# #816: Geräteübergreifender Stack-Verlauf. Ein Snapshot = eine Stack-
# Komposition (Trail + Position) je Nutzer und History-Bucket
# (history_key, z. B. "knowledge.stack.history"). Dedup über die finale
# Card-Folge — identisch zur bisherigen localStorage-Semantik
# (lib/blade_stack_history.js); der Client cached weiterhin lokal.
class StackSnapshot < ApplicationRecord
  MAX_RECENT = 10  # wie NOTE_STACK_HISTORY_MAX clientseitig

  belongs_to :actor

  validates :history_key, :dedup_key, :saved_at, presence: true
  validates :trail, presence: true

  scope :for_bucket, ->(actor, key) { where(actor: actor, history_key: key) }

  def self.dedup_key_for(trail)
    Array(trail.last).join(",")
  end

  # Upsert nach Dedup-Key: gleiche End-Komposition = ein Eintrag, der
  # Jüngere gewinnt; pinned bleibt erhalten (ODER-Semantik). Non-pinned
  # werden je Bucket auf MAX_RECENT getrimmt.
  def self.record!(actor:, history_key:, trail:, current:, pinned: nil)
    dk = dedup_key_for(trail)
    raise ArgumentError, "leerer Trail" if dk.blank?
    snap = find_or_initialize_by(actor: actor, history_key: history_key, dedup_key: dk)
    snap.trail    = trail
    snap.current  = current.to_i.clamp(0, [trail.size - 1, 0].max)
    snap.pinned   = pinned.nil? ? (snap.pinned || false) : pinned
    snap.saved_at = Time.current
    snap.save!
    trim!(actor, history_key)
    snap
  end

  def self.trim!(actor, history_key)
    keep = for_bucket(actor, history_key).where(pinned: false)
             .order(saved_at: :desc).limit(MAX_RECENT).ids
    for_bucket(actor, history_key).where(pinned: false).where.not(id: keep).delete_all
  end

  def as_client_json
    { id: id, trail: trail, current: current, pinned: pinned,
      savedAt: saved_at.iso8601, dedupKey: dedup_key }
  end
end
