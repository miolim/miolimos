# #325 (Hans, 2026-05-24): Operationen am Work-Tree. Alle Methoden
# transaktional, inkl. Auto-Link der KI zum Topic, falls noch nicht
# Material.
#
# Spec-Punkte aus #325:
#   - WorkNode erzeugen (KI in Tree ziehen) — `create`.
#   - Rolle aendern — `update_role`.
#   - Position aendern (Drag/Drop innerhalb Geschwistern) — `reorder`.
#   - Parent aendern (Section verschieben) — `reparent`.
#   - WorkNode entfernen (KI bleibt, nur die Tree-Position
#     verschwindet) — `remove`.
class WorkNodeOps
  class Error < StandardError; end

  # Erzeugt einen neuen Work-Node. Auto-Link der KI ans Topic, falls
  # noch nicht verknuepft. `position`-Default: am Ende der
  # Geschwister. #592: Knoten gehoeren zu einem TopicTree — ohne
  # expliziten `tree` wird der des Parents bzw. der Default-Work-Tree
  # des Topics genutzt (Abwaertskompatibilitaet).
  def self.create(topic:, knowledge_item:, parent: nil, role: "content", position: nil, tree: nil)
    ActiveRecord::Base.transaction do
      raise Error, "parent muss zum Topic gehoeren" if parent && parent.topic_id != topic.id

      tree ||= parent&.tree || topic.default_work_tree
      raise Error, "tree muss zum Topic gehoeren" if tree.topic_id != topic.id
      raise Error, "parent muss zum gleichen Baum gehoeren" if parent && parent.tree_id != tree.id

      ensure_material!(topic, knowledge_item)
      siblings = tree.nodes.where(parent_id: parent&.id)
      pos = position || (siblings.maximum(:position).to_i + 1)
      # Wenn position mitten in der Reihe — Lueckmachen.
      siblings.where("position >= ?", pos).update_all("position = position + 1")

      WorkNode.create!(
        topic: topic, tree: tree, parent: parent,
        knowledge_item_uuid: knowledge_item.uuid,
        role: role, position: pos
      )
    end
  end

  # #592: Junktor am Eltern-Knoten (and|or|nil) — bestimmt, wie die
  # Kinder verfeinern (UND = Zerlegung, ODER = Auswahl).
  def self.update_junctor(node, junctor)
    junctor = junctor.presence
    raise Error, "invalid junctor" unless junctor.nil? || WorkNode::JUNCTORS.include?(junctor)
    node.update!(junctor: junctor)
    node
  end

  # #592: IST-Markierung — genau EIN gewaehlter Ast je ODER-Verzweigung;
  # Setzen raeumt die Geschwister ab.
  def self.choose(node)
    ActiveRecord::Base.transaction do
      node.tree.nodes.where(parent_id: node.parent_id).where.not(id: node.id)
          .update_all(chosen: false)
      node.update!(chosen: true)
    end
    node
  end

  def self.unchoose(node)
    node.update!(chosen: false)
    node
  end

  def self.update_role(node, new_role)
    raise Error, "invalid role" unless WorkNode::ROLES.include?(new_role)
    node.update!(role: new_role)
    node
  end

  # Verschiebt einen Node innerhalb seiner Geschwister auf eine neue
  # Position (1-basiert). Re-Indiziert die Geschwister konsistent.
  def self.reorder(node, new_position)
    ActiveRecord::Base.transaction do
      siblings = node.tree.nodes.where(parent_id: node.parent_id).order(:position).to_a
      siblings.delete(node)
      idx = [[new_position - 1, 0].max, siblings.size].min
      siblings.insert(idx, node)
      siblings.each_with_index { |s, i| s.update_column(:position, i + 1) }
    end
    node.reload
  end

  # Setzt einen neuen Parent (oder nil = Top-Level). Default-Position:
  # Ende der neuen Geschwister. Zyklen-Check.
  def self.reparent(node, new_parent, position: nil)
    ActiveRecord::Base.transaction do
      if new_parent && new_parent.topic_id != node.topic_id
        raise Error, "new_parent muss zum gleichen Topic gehoeren"
      end
      if new_parent && new_parent.tree_id != node.tree_id
        raise Error, "new_parent muss zum gleichen Baum gehoeren"
      end
      raise Error, "Zyklus" if new_parent && descendants_of(node).include?(new_parent.id)

      old_siblings = node.tree.nodes
                          .where(parent_id: node.parent_id)
                          .where.not(id: node.id).order(:position).to_a
      old_siblings.each_with_index { |s, i| s.update_column(:position, i + 1) }

      new_siblings = node.tree.nodes
                          .where(parent_id: new_parent&.id)
                          .where.not(id: node.id)
      pos = position || (new_siblings.maximum(:position).to_i + 1)
      new_siblings.where("position >= ?", pos).update_all("position = position + 1")

      node.update!(parent: new_parent, position: pos)
    end
    node.reload
  end

  # Loescht den Node + alle Nachfahren. KI bleibt unangetastet.
  def self.remove(node)
    node.destroy!
  end

  # #325 (Hans, 2026-05-24): Indent — macht den Node zum Kind des
  # VORIGEN Geschwisters. Funktioniert nur, wenn ein voriges
  # Geschwister existiert.
  def self.indent(node)
    ActiveRecord::Base.transaction do
      siblings = node.tree.nodes
                     .where(parent_id: node.parent_id).order(:position).to_a
      idx = siblings.index(node)
      raise Error, "Indent unmoeglich — kein voriges Geschwister." if idx.nil? || idx == 0
      new_parent = siblings[idx - 1]
      reparent(node, new_parent)
    end
  end

  # Outdent — macht den Node zum Geschwister seines Parents, direkt
  # NACH dem Parent eingefuegt. Funktioniert nur, wenn ein Parent
  # existiert.
  def self.outdent(node)
    raise Error, "Outdent unmoeglich — Node ist bereits Top-Level." unless node.parent
    ActiveRecord::Base.transaction do
      grandparent = node.parent.parent
      parent_pos  = node.parent.position
      reparent(node, grandparent, position: parent_pos + 1)
    end
  end

  # —— intern ——————————————————————————————

  def self.ensure_material!(topic, knowledge_item)
    return if topic.knowledge_items.where(uuid: knowledge_item.uuid).exists?
    topic.knowledge_item_topics.create!(knowledge_item: knowledge_item)
  end

  def self.descendants_of(node)
    ids = Set.new
    stack = node.children.to_a
    while (n = stack.pop)
      ids << n.id
      stack.concat(n.children.to_a)
    end
    ids
  end
end
