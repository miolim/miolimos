# #1660: Nächtlicher Lauf, der die Sitzungsprotokolle einliest (siehe
# AgentUsage::Import). Läuft auf dem Server, auf dem die Agenten arbeiten —
# die Protokolle liegen dort im Home-Verzeichnis.
class AgentUsageImportJob < ApplicationJob
  queue_as :background

  def perform(tage: 45)
    ergebnis = AgentUsage::Import.call(tage: tage)
    Rails.logger.info("AgentUsageImportJob: #{ergebnis.inspect}")
    ergebnis
  end
end
