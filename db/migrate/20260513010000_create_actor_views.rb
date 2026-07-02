class CreateActorViews < ActiveRecord::Migration[8.1]
  def change
    # #160: User-History — protokolliert, wann ein Actor welche Entität
    # angeschaut (oder bearbeitet) hat. Polymorph, damit KIs / Tasks /
    # Sources / Awaitings / Topics dieselbe Tabelle teilen. Aufnahme-
    # Schwelle (3s) wird client-seitig im view-tracker-Controller
    # enforced; der Server speichert nur, was reinkommt.
    create_table :actor_views do |t|
      t.references :actor, null: false, foreign_key: true
      t.references :viewable, polymorphic: true, null: false
      t.datetime :viewed_at, null: false
      t.integer  :duration_ms, default: 0, null: false
      t.boolean  :was_edited,  default: false, null: false
      # Optional: anonymer Browser-Session-Token, gesetzt einmal pro
      # Browser-Session in sessionStorage. Erlaubt es, parallele
      # Sitzungen zu unterscheiden, ohne PII zu speichern.
      t.string   :session_token

      t.timestamps
    end

    # Listen-Abfrage: alle Views eines Actors, jüngste zuerst.
    add_index :actor_views, [:actor_id, :viewed_at], order: { viewed_at: :desc },
              name: "idx_actor_views_by_actor_time"

    # Dedupe-Abfrage: "habe ich diese Entität in der letzten Minute
    # schon angeschaut?" — gleicher Actor, gleiche Entität, viewed_at
    # absteigend.
    add_index :actor_views,
              [:actor_id, :viewable_type, :viewable_id, :viewed_at],
              name: "idx_actor_views_dedupe"
  end
end
