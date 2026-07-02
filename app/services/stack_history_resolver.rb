# #434 Teil 2 (Hans, 2026-06-01): Loest eine Liste von Stack-IDs (DOM-uuids
# aus dem ?stack=-Param / Verlauf — z.B. "task:5", "list:topic:demo",
# "list:tasks", KI-UUID) zu Anzeige-Labels auf, damit der Verlauf-Drawer auf
# JEDEM Stack echte Card-Titel zeigen kann (nicht nur im Wissensbereich).
# Reuse: BladeStackLoader.parse() macht bereits Token -> Record.
class StackHistoryResolver
  LIST_LABELS = {
    "tasks"          => "Aufgaben",
    "dashboard"      => "Dashboard",
    "knowledge_items"=> "Wissen",
    "persons"        => "Personen",
    "sources"        => "Quellen",
    "awaitings"      => "Wartend",
    "communications" => "Kommunikation",
    "inbox_items"    => "Inbox",
    "pinned"         => "Gepinnt",
    "history"        => "Verlauf",
    "tags"           => "Tags",
    "topics"         => "Themen",
  }.freeze

  # ids -> [{uuid:<id>, title:, item_type:}] (Shape wie stack_history_controller erwartet).
  def self.resolve(ids)
    ids = Array(ids).map(&:to_s).reject(&:blank?)
    return [] if ids.empty?
    by_uuid = BladeStackLoader.parse(ids.join(",")).index_by(&:stack_uuid)
    ids.map do |id|
      it = by_uuid[id]
      if it
        { uuid: id, title: label_for(it), item_type: kind_for(it) }
      else
        { uuid: id, title: nil, item_type: "missing" }  # geloescht/unbekannt
      end
    end
  end

  def self.label_for(it)
    case it.kind
    when :tag_list then "Tag: #{it.id}"
    when :list     then LIST_LABELS[it.id] || it.id.to_s.humanize
    else
      r = it.record
      r && (r.try(:title).presence || r.try(:name).presence ||
            r.try(:subject).presence || r.try(:display_label).presence || it.id)
    end
  end

  # fuer die Emoji-/Icon-Wahl im Drawer: bei KIs der item_type, sonst die kind.
  def self.kind_for(it)
    it.kind == :ki ? (it.record&.item_type.presence || "ki") : it.kind.to_s
  end
end
