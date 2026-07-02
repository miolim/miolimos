# #630 (Hans, 2026-06-12): Referenz eines Blades in die Zwischenablage —
# als Wikilink, wo es eine Syntax gibt (KI [[Titel]], Aufgabe [[#id]],
# Quelle [[&slug]]), sonst als URL. Der Button sitzt im Blade-Spine
# (shared/_blade_spine) und nutzt den copy-clipboard-Controller.
module BladeRefsHelper
  # Zeichen, die die Wikilink-Syntax brechen — dann lieber [[uuid]]
  # (löst genauso auf und rendert den Titel).
  WIKILINK_UNSAFE = /[\[\]|#^]/

  # Index-Stack-Seite je Blade-Kind für die URL-Variante. Fallback ist
  # /dashboard — jede Stack-Seite rendert jedes Kind, Dashboard ist die
  # neutralste.
  URL_BASE = {
    "topiclist"     => "/topics",
    "topicrender"   => "/topics",
    "topicrefs"     => "/topics",
    "treefocus"     => "/topics",
    "taglist"       => "/tags",
    "kirefs"        => "/knowledge_items",
    "awaiting"      => "/awaitings",
    "communication" => "/communications",
    "document"      => "/documents",
    "invoiceline"   => "/documents",
    "settings"      => "/settings",
    "settingssub"   => "/settings",
  }.freeze

  # Listen-Kind → Index-Seite (die Seite IST die Liste).
  LIST_BASE = {
    "tasks" => "/tasks", "calendar" => "/calendar", "awaitings" => "/awaitings",
    "communications" => "/communications", "sources" => "/sources",
    "inbox_items" => "/inbox", "history" => "/history",
    "time_entries" => "/time_entries", "documents" => "/documents",
    "dashboard" => "/dashboard", "knowledge_items" => "/knowledge_items",
    "settings" => "/settings", "topics" => "/topics", "pinned" => "/pinned",
  }.freeze

  # Kopier-Text für ein Blade (stack_id = DOM-uuid, z. B. "task:123",
  # "src:<slug>", bare KI-uuid). nil = kein sinnvolles Ziel (kein Button).
  def blade_ref_payload(stack_id)
    sid = stack_id.to_s.strip
    return nil if sid.blank?
    kind, _, rest = sid.partition(":")
    return ki_wikilink(sid) if rest.blank?   # ohne Prefix = KI-uuid

    case kind
    when "task"      then "[[##{rest}]]"
    when "src"       then "[[&#{rest}]]"
    when "topic"     then ref_url("/topics/#{rest}")
    when "inboxitem" then ref_url("/inbox/#{rest}")
    when "list"      then list_ref_url(rest)
    else
      ref_url("#{URL_BASE.fetch(kind, '/dashboard')}?stack=#{ERB::Util.url_encode(sid)}")
    end
  end

  # Kompakter Spine-Button; rendert nichts, wenn es keine Referenz gibt.
  def blade_copy_button(stack_id)
    payload = blade_ref_payload(stack_id)
    return "".html_safe if payload.blank?
    is_wikilink = payload.start_with?("[[")
    button_tag(icon("copy", size: "w-3.5 h-3.5"),
      type:  "button",
      title: is_wikilink ? "Wikilink kopieren" : "Link kopieren",
      "aria-label": "Referenz in die Zwischenablage kopieren",
      data: { controller: "copy-clipboard",
              action: "click->copy-clipboard#copy",
              copy_clipboard_content_value: payload,
              copy_clipboard_toast_value: "#{is_wikilink ? 'Wikilink' : 'Link'} kopiert: #{payload.truncate(60)}" },
      class: "shrink-0 p-0.5 rounded text-slate-400 hover:text-slate-700 hover:bg-slate-200 cursor-pointer")
  end

  private

  def ki_wikilink(uuid)
    item = KnowledgeItem.find_by(uuid: uuid)
    return nil unless item
    title = item.title.to_s
    # Titel mit Syntax-Brechern (oder leer): [[uuid]] löst der Resolver
    # genauso auf und zeigt den Titel an.
    (title.present? && title !~ WIKILINK_UNSAFE) ? "[[#{title}]]" : "[[#{item.uuid}]]"
  end

  def list_ref_url(rest)
    # list:topic:<slug>[:tab] → Topic-Seite; list:tag:<name> → Tags-Stack.
    sub, _, sub_id = rest.partition(":")
    return ref_url("/topics/#{sub_id.split(':').first}") if sub == "topic" && sub_id.present?
    return ref_url("/tags?stack=#{ERB::Util.url_encode("list:#{rest}")}") if sub == "tag"
    base = LIST_BASE[rest]
    base ? ref_url(base) : ref_url("/dashboard?stack=#{ERB::Util.url_encode("list:#{rest}")}")
  end

  def ref_url(path)
    "#{request.base_url}#{path}"
  end
end
