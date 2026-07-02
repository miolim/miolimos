# #536 P3: Benachrichtigungs-Drehscheibe des Portals.
# - Kunde schreibt  → Mail an Hans' Postfach (sein primärer Eingang) —
#   die Nachricht selbst liegt ohnehin als Communication im Posteingang.
# - Hans antwortet / gibt frei → gesammelter Ping an alle aktiven Zugänge
#   des Projekts (kein Mail-Gewitter: eine Mail pro Ereignis, kurzer Text,
#   Details stehen im Portal).
class PortalNotifier
  def self.customer_message(message, access)
    PortalMailer.customer_message_internal(message, access).deliver_later
  end

  def self.reply_posted(topic)
    each_access(topic) { |a| PortalMailer.update_ping(a, what: "Es gibt eine neue Antwort im Projekt-Thread.").deliver_later }
  end

  def self.content_shared(topic, what: "Es wurden neue Inhalte für Sie freigegeben.")
    each_access(topic) { |a| PortalMailer.update_ping(a, what: what).deliver_later }
  end

  def self.each_access(topic, &block)
    PortalAccess.active.where(topic: topic).find_each(&block)
  end
end
