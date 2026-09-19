# #1675: Räumt Posteingangs-Einträge auf, die auf „processing" hängen geblieben
# sind. Das passiert, wenn der Worker mitten im Lauf stirbt — bei JEDEM Deploy
# (Puma- und Queue-Neustart), bei einem Absturz, bei vollem Speicher. Der
# Prozessor kommt dann nie dazu, den Status zu setzen, und die Ansicht zeigt für
# „processing" nur den Warte-Kreisel: kein Knopf, kein Hinweis, für immer.
#
# Die Schwelle ist großzügig: Ein zweistündiges Video mit Whisper und
# Nachbearbeitung läuft lange, soll aber nicht abgeräumt werden. Wer nach
# Stunden noch „läuft", läuft nicht mehr.
class InboxStuckReaperJob < ApplicationJob
  queue_as :default

  SCHWELLE = 3.hours
  GRUND = "Die Verarbeitung wurde unterbrochen (z.B. durch einen Neustart) und nicht " \
          "abgeschlossen. Bitte erneut starten."

  def perform
    haengend = InboxItem.where(status: "processing").where(updated_at: ...SCHWELLE.ago)
    anzahl = haengend.update_all(status: "failed", error_message: GRUND, updated_at: Time.current)
    Rails.logger.warn("InboxStuckReaperJob: #{anzahl} hängende(n) Eintrag/Einträge auf failed gesetzt") if anzahl.positive?
    anzahl
  end
end
