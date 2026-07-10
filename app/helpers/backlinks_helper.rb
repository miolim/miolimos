# #501 (Hans, 2026-06-04): Einheitliche Darstellung/Navigation einer
# Backlink-Quelle. Eine Antwort-KI (item_type=reply) hat keinen eigenen
# Titel und soll nicht als nackte UUID erscheinen: stattdessen Titel des
# Parents (Aufgabe/KI) + „: Antwort", passendes Icon, und als
# Navigationsziel die ganze Aufgabe/KI (nav_uuid) mit Scroll auf die
# Antwort (scroll_to = reply_<uuid>). Genutzt vom backlinks-JSON-Endpoint
# UND von den Backlink-Sektionen (KI-Detail, KI-Show).
module BacklinksHelper
  def backlink_source_descriptor(k)
    # #953 Folge: Quelle kann auch eine Aufgabe sein (Beschreibung
    # referenziert per Wikilink) — Label wie ein Task-Wikilink.
    if k.is_a?(Task)
      { uuid: "task:#{k.id}", label: "##{k.id} #{k.title}", icon: "task",
        nav_uuid: "task:#{k.id}", scroll_to: nil }
    elsif k.reply? && k.parent_type == "Task" && (t = Task.find_by(id: k.parent_id_int))
      { uuid: k.uuid, label: "#{t.title}: Antwort", icon: "task",
        nav_uuid: "task:#{t.id}", scroll_to: "reply_#{k.uuid}" }
    elsif k.reply? && k.parent_type == "KnowledgeItem" && (p = KnowledgeItem.find_by(uuid: k.parent_uuid))
      { uuid: k.uuid, label: "#{p.title}: Antwort", icon: "ki",
        nav_uuid: p.uuid, scroll_to: "reply_#{k.uuid}" }
    else
      { uuid: k.uuid, label: k.title.presence || "(ohne Titel)", icon: "ki",
        nav_uuid: k.uuid, scroll_to: nil }
    end
  end

  # #953 Folge: href einer Backlink-Quelle (KI-Pfad bzw. Task-Stack).
  def backlink_source_path(k)
    k.is_a?(Task) ? tasks_path(stack: "task:#{k.id}") : knowledge_item_path(k.uuid)
  end

  # #953 Folge: Icon einer Backlink-Quelle — Tasks + Antwort-Quellen
  # tragen das Aufgaben-Icon, sonst das KI-Typ-Icon.
  def backlink_source_icon(k, descriptor)
    descriptor[:icon] == "task" ? icon("tasks", size: "w-4 h-4") : knowledge_type_icon(k)
  end
end
