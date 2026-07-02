# #573: Ereignisse/Termine — EINE Entität für beide Blickrichtungen
# (geplant = Zukunft, dokumentiert = Vergangenheit). Schlank: Zeitpunkt/
# Dauer, optionaler Projekt-Bezug, optionaler Communication-Link (z.B.
# dokumentierter Anruf), portal_visible für Kundenportal + Export.
class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string   :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string   :location
      t.text     :description
      t.references :topic, foreign_key: true            # optional: Projekt/Thema
      t.references :creator, foreign_key: { to_table: :actors }
      t.references :communication, foreign_key: true    # z.B. Anruf-Doku
      t.boolean  :portal_visible, null: false, default: false
      t.timestamps
    end
    add_index :events, :starts_at
  end
end
