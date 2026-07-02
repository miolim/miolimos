# #387 Phase B (Hans, 2026-05-28): Endpoint fuer den Backlink-Counter
# eines Color-Highlight-Ankers. Right-Click-Menue auf einer `<mark id>`
# laedt diesen Endpoint, zeigt die Zahl im Bar an.
# #387 Phase 2 (Hans, 2026-05-30): Tag-Editor-Endpoints.
class HighlightsController < ApplicationController
  def backlinks_count
    anchor = params[:anchor].to_s
    if anchor !~ /\A(?:[a-f0-9]{8}|[a-z0-9]{6})\z/
      render json: { error: "invalid anchor" }, status: :unprocessable_entity
      return
    end
    needle    = "[[^#{anchor}]]"
    ki_count   = KnowledgeItem.where("body LIKE ?", "%#{needle}%").count
    task_count = Task.where("description LIKE ?", "%#{needle}%").count
    render json: { count: ki_count + task_count }
  end

  # Aktuelle Tags eines Highlight-Ankers. Der Body ist die Quelle der
  # Wahrheit (Inline-Suffix `…==^anchor#tag1#tag2`); der KnowledgeItemAnchor-
  # Record ist nur ein Sync-Abbild und kann fuer Highlight-Anker fehlen.
  def tags
    anchor = params[:anchor].to_s
    return render(json: { error: "invalid anchor" }, status: 422) if anchor !~ /\A(?:[a-f0-9]{8}|[a-z0-9]{6})\z/

    # #447 (Hans, 2026-06-01): Wenn die KI bekannt ist (Frontend schickt ?ki=),
    # Tags direkt aus dem Body parsen — robust auch ohne Anchor-Record.
    item = item_for_anchor(anchor)
    if item
      body = FileProxy.read_body(actor: current_actor, knowledge_item: item)
      return render(json: { tags: parse_anchor_tags(body, anchor) })
    end
    rec = KnowledgeItemAnchor.find_by(anchor: anchor)
    render json: { tags: rec ? Array(rec.tags) : [] }
  end

  # PATCH-Endpoint: nimmt die gewuenschte komplette Tag-Liste, updated
  # die MD-Quelle (Inline-Syntax `==…==^anchor#tag1#tag2`). Save
  # triggert Anchors.sync_for → DB ist auch konsistent.
  def update_tags
    anchor = params[:anchor].to_s
    return render(json: { error: "invalid anchor" }, status: 422) if anchor !~ /\A(?:[a-f0-9]{8}|[a-z0-9]{6})\z/

    # #447 (Hans, 2026-06-01): KI ueber ?ki= finden (Frontend kennt sie) statt
    # ueber den KnowledgeItemAnchor-Record — der fehlte fuer Highlight-Anker
    # und fuehrte zu 404 "Konnte Tags nicht speichern". Fallback: Anchor-Record.
    item = item_for_anchor(anchor)
    return render(json: { error: "knowledge item not found" }, status: 404) unless item

    new_tags = Array(params[:tags]).map { |t| t.to_s.strip.downcase }.reject(&:blank?).uniq
    body     = FileProxy.read_body(actor: current_actor, knowledge_item: item)
    new_body = rewrite_anchor_tags(body, anchor, new_tags)

    if new_body != body
      FileProxy.update(actor: current_actor, knowledge_item: item, content: new_body)
    end

    render json: { tags: new_tags }
  end

  private

  # Findet die KI zu einem Highlight-Anker: bevorzugt ueber die vom Frontend
  # mitgeschickte UUID (?ki=), sonst ueber den (evtl. fehlenden) Anchor-Record.
  def item_for_anchor(anchor)
    if params[:ki].present?
      item = KnowledgeItem.find_by(uuid: params[:ki])
      return item if item
    end
    rec = KnowledgeItemAnchor.find_by(anchor: anchor)
    rec && KnowledgeItem.find_by(uuid: rec.knowledge_item_uuid)
  end

  # Liest die `#tag`-Suffixe hinter `==…==^anchor` aus dem Body.
  def parse_anchor_tags(body, anchor)
    m = body.to_s.match(/==[a-z]+\|[^=]{1,800}?==\^#{Regexp.escape(anchor)}((?:#[a-zA-Z0-9_-]+)+)/m)
    return [] unless m
    m[1].scan(/#([a-zA-Z0-9_-]+)/).flatten
  end

  # Findet den Highlight-Wrap mit dem 8-Hex-Anker und ersetzt den
  # bestehenden Tag-Suffix (falls vorhanden) durch die neue Tag-Liste.
  # `tags` darf leer sein → Suffix wird entfernt.
  def rewrite_anchor_tags(body, anchor, tags)
    re = /(==[a-z]+\|[^=]{1,800}?==\^#{Regexp.escape(anchor)})(?:#[a-zA-Z0-9_-]+)*/m
    suffix = tags.any? ? tags.map { |t| "##{t}" }.join : ""
    body.sub(re, "\\1#{suffix}")
  end

  def controller_resource_type
    "KnowledgeItem"
  end
end
