# #630 (Hans, 2026-06-12): Referenz eines Blades in die Zwischenablage.
# Der Button sitzt im Blade-Spine (shared/_blade_spine) und nutzt den
# copy-clipboard-Controller.
#
# #1617 (Hans): „Es wird grundsätzlich immer der Link kopiert. Mit
# UMSCHALT+Mausklick wird der Wikilink kopiert, falls vorhanden." — Jede
# Card hat einen Link; KI [[Titel]], Aufgabe [[#id]] und Quelle [[&slug]]
# haben zusätzlich einen Wikilink.
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

  # Referenzen einer Card (stack_id = DOM-uuid, z. B. "task:123",
  # "src:<slug>", bare KI-uuid): { link:, wikilink: }. wikilink fehlt, wo es
  # keine Syntax gibt. nil = kein sinnvolles Ziel (kein Button). Die Links
  # zeigen dorthin, wohin auch der gerenderte Wikilink führt.
  def blade_refs(stack_id)
    sid = stack_id.to_s.strip
    return nil if sid.blank?
    kind, _, rest = sid.partition(":")
    return ki_refs(sid) if rest.blank?   # ohne Prefix = KI-uuid

    case kind
    when "task"      then { link: ref_url("/tasks?stack=task:#{rest}"), wikilink: "[[##{rest}]]" }
    when "src"       then { link: ref_url("/sources/#{rest}"), wikilink: "[[&#{rest}]]" }
    when "topic"     then { link: ref_url("/topics/#{rest}") }
    when "inboxitem" then { link: ref_url("/inbox/#{rest}") }
    when "help"      then { link: ref_url("/help/#{rest}") }   # #1677 (aus immoOS #1658)
    when "list"      then { link: list_ref_url(rest) }
    else
      { link: ref_url("#{URL_BASE.fetch(kind, '/dashboard')}?stack=#{ERB::Util.url_encode(sid)}") }
    end
  end

  # Kompakter Spine-Button; rendert nichts, wenn es keine Referenz gibt.
  # Klick kopiert den Link, Umschalt+Klick den Wikilink (falls vorhanden).
  def blade_copy_button(stack_id)
    refs = blade_refs(stack_id)
    return "".html_safe if refs.blank?
    link, wikilink = refs.values_at(:link, :wikilink)
    button_tag(icon("copy", size: "w-3.5 h-3.5"),
      type:  "button",
      title: wikilink ? t("shared.blade_copy.title_with_wikilink") : t("shared.blade_copy.title"),
      "aria-label": t("shared.blade_copy.aria"),
      data: { controller: "copy-clipboard",
              action: "click->copy-clipboard#copy",
              copy_clipboard_content_value: link,
              copy_clipboard_toast_value: t("shared.blade_copy.link_copied", ref: link.truncate(60)),
              copy_clipboard_wikilink_value: wikilink,
              copy_clipboard_wikilink_toast_value: wikilink && t("shared.blade_copy.wikilink_copied", ref: wikilink.truncate(60)) }.compact,
      class: "shrink-0 p-0.5 rounded text-slate-400 hover:text-slate-700 hover:bg-slate-200 cursor-pointer")
  end

  private

  def ki_refs(uuid)
    item = KnowledgeItem.find_by(uuid: uuid)
    return nil unless item
    title = item.title.to_s
    # Titel mit Syntax-Brechern (oder leer): [[uuid]] löst der Resolver
    # genauso auf und zeigt den Titel an.
    wikilink = (title.present? && title !~ WIKILINK_UNSAFE) ? "[[#{title}]]" : "[[#{item.uuid}]]"
    { link: ref_url("/knowledge_items?stack=#{item.uuid}"), wikilink: wikilink }
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
