require "open3"

# Bestands-KIs hatten vor der creator-Migration keinen Creator. Diese
# Klasse zieht ihn aus dem Daten-Git nach: für jeden KI-Datensatz ohne
# creator_id holen wir den ersten Commit, der dessen file_path eingeführt
# hat, und mappen Author-Email/Name auf einen Actor.
#
# Idempotent: Datensätze, die wir nicht zuordnen können, bleiben mit
# creator_id = NULL — die Methode kann später ohne Schaden erneut laufen,
# z.B. nachdem ein neuer Actor angelegt wurde.
class KnowledgeCreatorBackfill
  Stats = Struct.new(:scanned, :resolved, :resolved_via_inbox, :unresolved,
                     keyword_init: true)

  def self.run(logger: Rails.logger)
    new(logger: logger).run
  end

  def initialize(logger:)
    @logger = logger
    @actor_cache_by_email = {}
    @actor_cache_by_name  = {}
  end

  def run
    base = FileProxy::BASE_PATH
    unless File.directory?(File.join(base, ".git"))
      @logger.warn("KnowledgeCreatorBackfill: kein Git-Repo unter #{base} — abgebrochen.")
      return Stats.new(scanned: 0, resolved: 0, resolved_via_inbox: 0, unresolved: 0)
    end

    scanned = resolved = resolved_via_inbox = unresolved = 0
    KnowledgeItem.with_discarded.where(creator_id: nil).find_each do |item|
      scanned += 1
      author_name, author_email = first_commit_author(base, item.file_path)
      actor = lookup_actor(author_email, author_name)

      # Sekundär: KIs aus der Inbox-Pipeline haben oft keinen Git-Commit
      # (still gescheiterter `git_commit`-rescue). Fallback auf den
      # Creator des verknüpften Inbox-Items, wenn vorhanden.
      if actor.nil? && item.inbox_item_id
        actor = item.inbox_item&.creator
        if actor
          resolved_via_inbox += 1
        end
      end

      if actor
        item.update_columns(creator_id: actor.id)
        resolved += 1
      else
        @logger.info("KnowledgeCreatorBackfill: #{item.uuid} (#{item.file_path}) " \
                     "— Author '#{author_name}' <#{author_email}> nicht zuordenbar")
        unresolved += 1
      end
    end
    Stats.new(scanned: scanned, resolved: resolved,
              resolved_via_inbox: resolved_via_inbox, unresolved: unresolved)
  end

  private

  # Liefert [author_name, author_email] des ältesten Git-Commits zur
  # Datei. Wir nehmen NICHT `--diff-filter=A`, weil File-Renames per
  # `git mv` als "M" zählen — kombiniert mit `--follow` würde das den
  # Add-Commit unterdrücken und gar nichts zurückliefern. Stattdessen
  # nehmen wir den ältesten Commit zur aktuellen Pfad-Identität;
  # `--follow` zieht Renames mit. Heuristisch ist das der Anlege-Akt.
  def first_commit_author(base, file_path)
    out, _err, status = Open3.capture3(
      "git", "-C", base.to_s, "log",
      "--follow", "--reverse",
      "--format=%aN%x09%aE", "--", file_path
    )
    return [nil, nil] unless status.success?
    line = out.lines.first.to_s.chomp
    return [nil, nil] if line.empty?
    name, email = line.split("\t", 2)
    [name.to_s.strip.presence, email.to_s.strip.presence]
  end

  def lookup_actor(email, name)
    return nil if email.blank? && name.blank?
    if email.present?
      @actor_cache_by_email[email] ||= Actor.where("LOWER(email) = ?", email.downcase).first
      return @actor_cache_by_email[email] if @actor_cache_by_email[email]
    end
    if name.present?
      @actor_cache_by_name[name] ||= Actor.where("LOWER(name) = ?", name.downcase).first
      return @actor_cache_by_name[name]
    end
    nil
  end
end
