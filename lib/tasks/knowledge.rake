namespace :knowledge do
  desc "Re-indiziert das Dateisystem (~/miolimos/ bzw. MIOLIMOS_DATA_PATH) in die DB"
  task reindex: :environment do
    stats = KnowledgeIndexer.run
    puts "KnowledgeIndexer:"
    puts "  scanned:    #{stats.scanned}"
    puts "  created:    #{stats.created}"
    puts "  updated:    #{stats.updated}"
    puts "  unchanged:  #{stats.unchanged}"
    puts "  orphaned:   #{stats.orphaned}"
    puts "  references: #{stats.references}"
  end

  desc "Backfill: creator_id aus dem ersten Git-Commit pro KI-Datei nachziehen"
  task backfill_creators: :environment do
    stats = KnowledgeCreatorBackfill.run
    puts "KnowledgeCreatorBackfill:"
    puts "  scanned:            #{stats.scanned}"
    puts "  resolved (gesamt):  #{stats.resolved}"
    puts "    davon via Inbox:  #{stats.resolved_via_inbox}"
    puts "  unresolved:         #{stats.unresolved}"
  end

  desc "Backfill: alte item_type-Strings im Frontmatter auf neue Konsolidierung umschreiben"
  task backfill_item_types: :environment do
    actor = HumanActor.find_by(email: "hans@miolim.de") || HumanActor.first
    abort "Kein HumanActor gefunden" unless actor

    stats = KnowledgeItemTypeBackfill.run(actor: actor)
    puts "KnowledgeItemTypeBackfill:"
    puts "  scanned:         #{stats.scanned}"
    puts "  rewritten:       #{stats.rewritten}"
    puts "  already_current: #{stats.already_current}"
    puts "  no_frontmatter:  #{stats.no_frontmatter}"
  end

  desc "Pusht lokale Änderungen in ~/miolimos/ zum Git-Remote"
  task push: :environment do
    path = FileProxy::BASE_PATH
    unless File.directory?(File.join(path, ".git"))
      abort "Kein Git-Repo unter #{path}"
    end

    Dir.chdir(path) do
      ok = system("git", "push")
      abort "git push fehlgeschlagen" unless ok
    end
  end
end
