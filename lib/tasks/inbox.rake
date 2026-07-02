namespace :inbox do
  desc "Importiert MD-Dateien aus ~/miolimos-inbox/ ins Knowledge-System"
  task import: :environment do
    actor = HumanActor.find_by(email: "hans@miolim.de") || HumanActor.first
    raise "Kein Human-Actor gefunden" unless actor

    Current.actor = actor
    results = WikiImporter.run(actor: actor)
    if results.empty?
      puts "Inbox leer."
    else
      results.each { |r| puts "  #{r}" }
      created  = results.count { |r| r.outcome == :created }
      appended = results.count { |r| r.outcome == :appended }
      errors   = results.count { |r| r.outcome == :error }
      puts "→ #{created} angelegt, #{appended} angehängt, #{errors} Fehler"
    end

    # Re-Index, damit DB-Zustand konsistent ist (FileProxy.create/update
    # haben das schon gemacht, aber ein Re-Index zur Sicherheit).
    Rake::Task["knowledge:reindex"].invoke if results.any?
  end
end
