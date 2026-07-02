# #343 (Hans, 2026-05-25): Extrahiert alle `[[Title]]`-Wikilinks aus
# dem Body einer KI in Source-Reihenfolge, dedupliziert und
# resolviert zu KnowledgeItems.
#
# Genutzt vom Reference-Blade (`refs:ki:<uuid>`), das die Wikilink-
# Ziele einer KI gerendert auflistet. #352-follow: auch fuer ein
# komplettes Topic (`refs:topic:<slug>`) — sammelt ueber alle KIs
# im Work-Tree.
class WikilinkTargets
  # Liefert Array<KnowledgeItem> in Source-Reihenfolge, ohne Duplikate.
  # Wikilinks ohne aufloesbares Ziel werden uebersprungen (kein „leerer
  # Slot"; das Reference-Blade soll nur tatsaechlich verlinkbare KIs
  # zeigen).
  def self.for(item)
    return [] if item.nil? || item.body.blank?
    collect_from_bodies([item.body])
  end

  # Sammelt alle Wikilink-Ziele aus den Bodies aller KIs im Work-Tree
  # eines Topics. Reihenfolge folgt dem Tree-Walk (Pre-Order); innerhalb
  # eines Bodies in Source-Reihenfolge. Dedupliziert ueber alle Bodies.
  def self.for_topic(topic)
    return [] if topic.nil?
    roots = topic.work_tree_roots.includes(:knowledge_item, children: :knowledge_item).to_a
    bodies = []
    visit = lambda do |node|
      ki = node.knowledge_item
      bodies << ki.body if ki && ki.deleted_at.nil? && ki.body.present?
      node.children.each { |c| visit.call(c) }
    end
    roots.each { |r| visit.call(r) }
    collect_from_bodies(bodies)
  end

  def self.collect_from_bodies(bodies)
    seen    = {}
    targets = []
    bodies.each do |body|
      body.to_s.scan(KnowledgeMarkdown::Wikilinks::WIKILINK_RE).each do |match|
        title = match[0].to_s.strip
        next if title.empty?
        target = KnowledgeMarkdown::Wikilinks.lookup_target(title)
        next unless target
        key = target.uuid
        next if seen[key]
        seen[key] = true
        targets << target
      end
    end
    # #602 S1-Nachzug: Das Refs-Blade rendert die VOLLEN Inhalte der
    # Ziele — ohne Filter wäre ein Wikilink auf ein fremdes Topic eine
    # Hintertür (Titel im Quelltext ist sichtbar, Inhalt darf es nicht
    # sein). Unsichtbare Ziele fallen raus wie nicht-auflösbare.
    return targets if targets.empty?
    visible = KnowledgeItem.visible_to(Current.actor)
                           .where(uuid: targets.map(&:uuid)).pluck(:uuid).to_set
    targets.select { |t| visible.include?(t.uuid) }
  end
end
