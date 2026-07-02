# #533 #2 (Hans, 2026-06-07): Grund, warum eine laufende Strecke geschlossen
# wurde — speist das Ereignis-Log in der Buchungs-Detailansicht.
#   paused     — Du hast manuell pausiert („Bearbeitung beendet")
#   superseded — ein anderer Timer wurde gestartet („Andere Aufgabe begonnen")
#   finished   — hart beendet (Stop)
class AddEndReasonToTimeSegments < ActiveRecord::Migration[8.1]
  def change
    add_column :time_segments, :end_reason, :string
  end
end
