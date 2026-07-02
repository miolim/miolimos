# #573 E3: minimaler ICS-Erzeuger (RFC 5545) — Events + Meilensteine als
# VEVENTs für den abonnierbaren Feed. Bewusst ohne Gem: das Format ist
# trivial, und wir kontrollieren jedes Feld.
class IcsExport
  def self.calendar(events:, milestones:)
    lines = [
      "BEGIN:VCALENDAR", "VERSION:2.0",
      "PRODID:-//miolimOS//Kalender//DE",
      "CALSCALE:GREGORIAN",
      "X-WR-CALNAME:miolimOS"
    ]
    events.find_each do |e|
      lines += vevent(uid: "event-#{e.id}@miolimos",
                      summary: e.title, starts_at: e.starts_at, ends_at: e.ends_at,
                      description: e.description, location: e.location)
    end
    milestones.find_each do |t|
      lines += vevent(uid: "milestone-#{t.id}@miolimos",
                      summary: "◆ Meilenstein: #{t.title}",
                      starts_at: t.due_date.beginning_of_day, all_day: true)
    end
    (lines + [ "END:VCALENDAR" ]).join("\r\n") + "\r\n"
  end

  def self.vevent(uid:, summary:, starts_at:, ends_at: nil, description: nil, location: nil, all_day: false)
    v = [ "BEGIN:VEVENT", "UID:#{uid}", "DTSTAMP:#{utc(Time.current)}" ]
    if all_day
      v << "DTSTART;VALUE=DATE:#{starts_at.strftime('%Y%m%d')}"
    else
      v << "DTSTART:#{utc(starts_at)}"
      v << "DTEND:#{utc(ends_at || starts_at + 1.hour)}"
    end
    v << "SUMMARY:#{esc(summary)}"
    v << "DESCRIPTION:#{esc(description)}" if description.present?
    v << "LOCATION:#{esc(location)}"       if location.present?
    v << "END:VEVENT"
    v
  end

  def self.utc(t)  = t.utc.strftime("%Y%m%dT%H%M%SZ")
  def self.esc(s)  = s.to_s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub(",", "\\,").gsub(";", "\;")
end
