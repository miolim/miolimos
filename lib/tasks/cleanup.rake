namespace :cleanup do
  desc "Räumt soft-gelöschte Tasks > 30 Tage hart aus der DB"
  task discarded_tasks: :environment do
    cutoff = 30.days.ago
    scope = Task.with_discarded.where("deleted_at < ?", cutoff)
    count = scope.count
    next puts "Nichts aufzuräumen." if count.zero?

    scope.find_each do |t|
      puts "  hard-delete ##{t.id} '#{t.title.truncate(40)}' (deleted #{t.deleted_at})"
      Task.with_discarded.find(t.id).destroy
    end
    puts "#{count} Tasks endgültig gelöscht."
  end

  desc "Räumt soft-gelöschte KnowledgeItems > 30 Tage (DB + .trash-Datei)"
  task discarded_knowledge_items: :environment do
    cutoff = 30.days.ago
    scope  = KnowledgeItem.with_discarded.where("deleted_at < ?", cutoff)
    count  = scope.count
    next puts "Nichts aufzuräumen." if count.zero?

    # Cleanup-Aktor: der erste (Admin-)HumanActor der Instanz (#806).
    actor = HumanActor.order(:id).first
    raise "Kein Human-Actor gefunden für Cleanup-Authoring" unless actor

    scope.find_each do |k|
      puts "  purge '#{k.title.truncate(40)}' (deleted #{k.deleted_at})"
      FileProxy.purge!(actor: actor, knowledge_item: k)
    end
    puts "#{count} KnowledgeItems endgültig gelöscht."
  end
end
