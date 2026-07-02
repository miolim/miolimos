# #501 (Hans, 2026-06-04): Einheitliche Darstellung/Navigation einer
# Backlink-Quelle. Eine Antwort-KI (item_type=reply) hat keinen eigenen
# Titel und soll nicht als nackte UUID erscheinen: stattdessen Titel des
# Parents (Aufgabe/KI) + „: Antwort", passendes Icon, und als
# Navigationsziel die ganze Aufgabe/KI (nav_uuid) mit Scroll auf die
# Antwort (scroll_to = reply_<uuid>). Genutzt vom backlinks-JSON-Endpoint
# UND von den Backlink-Sektionen (KI-Detail, KI-Show).
module BacklinksHelper
  def backlink_source_descriptor(k)
    if k.reply? && k.parent_type == "Task" && (t = Task.find_by(id: k.parent_id_int))
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
end
