# #1076: taeglicher Betriebsbericht an den Betreiber.
#
# Versand laeuft wie alle Mails ueber die Gmail-API (GmailSender setzt den
# Absender, wenn `from` leer bleibt) — deshalb hier kein `default from`.
#
# BEWUSSTE GRENZE: Diese Mail wird von der miolimOS-Instanz selbst verschickt.
# Steht sie, kommt kein Bericht. Das ist kein Versehen, sondern die zweite
# Haelfte des Entwurfs: Der Bericht geht taeglich raus, auch wenn alles gruen
# ist, damit sein AUSBLEIBEN das Signal ist. Fuer den Sofortfall haengt am
# Waechter-Skript zusaetzlich ein externer Alarmweg, der diese Maschine nicht
# braucht (ops/watchdog/miolimos-service-watch.sh).
class OpsMailer < ApplicationMailer
  def daily_report(report, to:)
    @report = report
    mail to: to, subject: report.subject
  end
end
