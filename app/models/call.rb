# #573/#574: dokumentierter Anruf — läuft als Communication (STI wie Email/
# PortalMessage): Richtung, Zeitpunkt (sent_at), Beteiligte (Mentions),
# Notiz im body. Erscheint damit im Posteingang/Projekt-Reiter wie jede
# andere Kommunikation und (über sein Event) im Kalender.
class Call < Communication
  # #765 (Hans, 2026-06-23): Dauer (Minuten) setzen/ändern und dabei die
  # Endzeit am verknüpften Event sowie die Zeitbuchung synchron halten.
  # Wird sowohl beim Anlegen (calendar#create_call) als auch beim
  # nachträglichen Bearbeiten (communications#update_call_duration) genutzt.
  # minutes <= 0 / leer entfernt Dauer, Endzeit und Zeitbuchung wieder.
  def apply_duration!(minutes, actor:)
    mins = minutes.to_i
    mins = nil unless mins.positive?
    update!(duration_minutes: mins)

    new_ends = mins ? sent_at + mins.minutes : nil
    event&.update!(ends_at: new_ends)

    te = TimeEntry.for_subject(self).order(:id).first
    if mins
      tp = topics.first
      if te
        te.update!(started_at: sent_at, ended_at: new_ends, topic: tp)
        te.time_segments.destroy_all
        te.time_segments.create!(started_at: sent_at, ended_at: new_ends)
      else
        TimeEntry.log_manual!(actor: actor, started_at: sent_at, minutes: mins,
                              topic: tp, subject: self, note: subject,
                              billable: tp&.billable? || false)
      end
    elsif te
      te.destroy   # Dauer entfernt → Zeitbuchung wieder entfernen
    end
    mins
  end
end
