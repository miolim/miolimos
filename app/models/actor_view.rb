class ActorView < ApplicationRecord
  # #160: User-History. Ein ActorView ist eine View-Session (oder ein
  # Batch-Update einer View-Session) eines Actors auf einer Entität.
  # Mehrere Updates derselben Session werden im Controller deduppt
  # (siehe upsert_for!) — die letzte Schreibe gewinnt mit dem höchsten
  # duration_ms.
  belongs_to :actor
  belongs_to :viewable, polymorphic: true

  # Welche viewable_types werden unterstützt? Liste hier zentral —
  # Controller validiert dagegen.
  TRACKABLE_TYPES = %w[KnowledgeItem Task Source Awaiting Topic].freeze

  validates :viewable_type, inclusion: { in: TRACKABLE_TYPES }
  validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }
  validates :viewed_at, presence: true

  scope :for_actor, ->(actor) { where(actor_id: actor.id) }
  scope :recent,    ->        { order(viewed_at: :desc) }

  # Upsert-Mechanismus: wenn der Actor dieselbe Entität in den letzten
  # `dedupe_window` Sekunden schon angeschaut hat, aktualisieren wir
  # diesen View (höhere duration_ms, oder erstmals was_edited=true).
  # Sonst legen wir einen neuen Datensatz an.
  #
  # Default-Fenster: 60s. So zählt "Tab kurz weg, dann wieder zurück"
  # innerhalb einer Minute als ein einziger View.
  def self.upsert_for!(actor:, viewable_type:, viewable_id:, duration_ms:, was_edited: false, session_token: nil, dedupe_window: 60.seconds)
    cutoff = dedupe_window.ago
    existing = where(actor_id: actor.id,
                     viewable_type: viewable_type,
                     viewable_id: viewable_id)
               .where("viewed_at >= ?", cutoff)
               .order(viewed_at: :desc)
               .first

    if existing
      new_duration = [existing.duration_ms, duration_ms.to_i].max
      new_edited   = existing.was_edited || was_edited
      existing.update!(duration_ms: new_duration, was_edited: new_edited,
                       session_token: existing.session_token || session_token)
      existing
    else
      create!(actor_id: actor.id,
              viewable_type: viewable_type,
              viewable_id: viewable_id,
              viewed_at: Time.current,
              duration_ms: duration_ms.to_i,
              was_edited: was_edited,
              session_token: session_token)
    end
  end

  # Distinct-Liste der letzten Views pro Entität — eine Zeile pro
  # (viewable_type, viewable_id). Für die History-Listen-Anzeige.
  scope :distinct_recent, -> {
    sql = <<~SQL
      SELECT DISTINCT ON (viewable_type, viewable_id) *
      FROM actor_views
      ORDER BY viewable_type, viewable_id, viewed_at DESC
    SQL
    from(Arel.sql("(#{sql}) AS actor_views"))
  }
end
