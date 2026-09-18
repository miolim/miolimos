# #1660: Token-Verbrauch der Agenten einlesen.
#
#   bin/rails agent_usage:import          # letzte 45 Tage
#   bin/rails agent_usage:import[120]     # längerer Zeitraum (Erstbefüllung)
namespace :agent_usage do
  desc "Sitzungsprotokolle der Agenten einlesen und verdichten"
  task :import, [:tage] => :environment do |_t, args|
    tage = (args[:tage] || 45).to_i
    ergebnis = AgentUsage::Import.call(tage: tage)
    puts "Gelesen: #{ergebnis[:dateien]} Dateien, geschrieben: #{ergebnis[:geschrieben]} Zeilen (#{tage} Tage)"
  end
end
