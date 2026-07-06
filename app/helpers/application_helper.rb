module ApplicationHelper
  # #602 S3: Sichtbarkeits-Badge — wer sieht dieses Objekt? Leitet sich
  # aus den Topic-Zuordnungen ab: ohne Topic = privat (Ersteller+Admins),
  # ein intern-öffentliches Topic dominiert (alle Nutzer), sonst die
  # Mitglieder der zugeordneten Themen.
  def visibility_badge(record)
    topics = record.respond_to?(:topics) ? record.topics.to_a : [record.topic].compact
    label, title =
      if topics.empty?
        ["privat", "Nur Ersteller und Admins sehen dieses Objekt"]
      elsif topics.any?(&:internal_public?)
        ["intern öffentlich", "Alle internen Nutzer sehen dieses Objekt"]
      else
        ["Mitglieder", "Sichtbar für Mitglieder von: #{topics.map(&:name).join(", ")} (+ Admins)"]
      end
    tag.span "👁 #{label}", title: title,
      class: "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[11px] "              "bg-slate-100 text-slate-500 whitespace-nowrap shrink-0 cursor-default"
  end

  # #268: Initialen Sidebar-Collapsed-State serverseitig kennen, damit
  # der Render direkt im richtigen Modus erfolgt (kein expand→collapse-
  # Flackern). Der Sidebar-Controller spiegelt die localStorage-
  # Persistenz in dieses Cookie.
  def sidebar_collapsed?
    request&.cookies&.[]("sidebar_collapsed") == "true"
  end

  # #271: Vorliebe-getriebene Data-Attribute fuer den blade-stack-
  # Controller (Card-Default-Breiten und Wheel-Werte). Wird ueber alle
  # blade-stack-Container hinweg via raw-Render hineingegossen, damit
  # nicht jeder Call-Site dieselben sechs Attribute auflisten muss.
  def blade_stack_pref_attrs
    return "" unless current_actor
    widths = current_actor.pref_card_widths
    wheel  = current_actor.pref_wheel
    %{data-blade-stack-card-widths-value='#{ERB::Util.html_escape(widths.to_json)}' } +
      %{data-blade-stack-wheel-threshold-value="#{wheel["threshold"]}" } +
      %{data-blade-stack-wheel-lock-ms-value="#{wheel["lock_ms"]}"}
  end

  # Kompakte Alters-Anzeige für Listen-Spalten und Header. Form: "5m",
  # "2h", "3d", "4w" — kommt ohne ActionView::TimeAgo-Locale aus
  # (rails-i18n liefert diese Strings nicht standardmäßig mit, weshalb
  # `time_ago_in_words` mit deutscher Locale "Translation missing"-
  # Fehler wirft). Die Funktion ist hier zentral, damit andere Listen
  # sie auch nutzen können.
  def compact_age(time)
    return "" if time.nil?
    seconds = (Time.current - time).to_i
    return "<1m" if seconds < 60
    return "#{seconds / 60}m"      if seconds < 3_600
    return "#{seconds / 3_600}h"   if seconds < 86_400
    return "#{seconds / 86_400}d"  if seconds < 604_800
    return "#{seconds / 604_800}w" if seconds < 31_536_000
    "#{seconds / 31_536_000}y"
  end

  # blade_kind/blade_id: optionales Plus-Icon, das den Sidebar-Eintrag
  # an den aktuellen Blade-Stack appendet (#163 Phase 5a). Bei gesetztem
  # blade_kind wird der Link mit einem Wrapper-Div um Link + Plus-Icon
  # herumgelegt; der Link bekommt flex-1, das Plus haengt rechts dran.
  def sidebar_link(label, path, icon_name = nil, blade_kind: nil, blade_id: nil, reset_stack_id: nil)
    active = current_page?(path) || (path != "/" && request.path.start_with?(path.split("?").first.to_s))
    # Icon sitzt in einer fixen w-5-Spalte und bleibt damit beim
    # Collapse exakt in derselben horizontalen Position. min-h-7 hält
    # die Reihe-Höhe konstant — sonst schrumpft die Höhe, wenn der
    # Label-Span hidden ist, und die Icons rücken vertikal zusammen.
    base   = "flex items-center gap-2 px-2 py-1 min-h-7 rounded hover:bg-slate-800"
    link_klass = blade_kind ? "flex-1 min-w-0 #{base}" : base
    klass  = active ? "#{link_klass} bg-slate-800 text-white" : link_klass
    icon_slot = content_tag(:span,
      icon_name ? icon(icon_name) : "".html_safe,
      class: "w-5 flex items-center justify-center shrink-0")
    # #154: Klick collapsed die hover-expandierte Desktop-Sidebar und
    # schließt das Mobile-Hamburger-Overlay.
    # #271: bei pref_sidebar_click_mode = "append" UND vorhandenem
    # blade_kind/blade_id wird der Link selber zum Append-Trigger
    # (blade-link-Controller), statt zur Seite zu navigieren.
    link_data = { action: "click->sidebar#hoverCollapse click->mobile-nav#close" }
    # #434 (Hans, 2026-06-01): Klick auf diese Liste, wenn sie das ERSTE Blade
    # des aktuellen Stacks ist -> Stack zuruecksetzen (Snapshot + frischer
    # Trail). Der blade-stack-Controller faengt den Klick ueber dieses
    # data-Attribut ab (capture-Phase); sonst normale Navigation. Fuer
    # list-Blades automatisch list:<id>, sonst explizit ueber reset_stack_id.
    reset_id = reset_stack_id || ("list:#{blade_id}" if blade_kind == "list" && blade_id)
    link_data[:"stack-reset-id"] = reset_id if reset_id
    if blade_kind && blade_id && current_actor&.pref_sidebar_click_mode == "append"
      link_data[:controller]              = "blade-link"
      link_data[:"blade-link-kind-value"] = blade_kind
      link_data[:"blade-link-id-value"]   = blade_id
      link_data[:action] = "click->blade-link#append #{link_data[:action]}"
    end
    link = link_to(path, class: klass, title: label, data: link_data) do
      safe_join([
        icon_slot,
        content_tag(:span, label, class: "truncate group-data-[collapsed=true]/sidebar:hidden")
      ])
    end
    return link unless blade_kind
    plus = render("shared/sidebar_blade_plus", kind: blade_kind, id: blade_id, title: label)
    content_tag(:div, safe_join([link, plus]), class: "flex items-center")
  end

  # #846: Anzeige-Label je Sidebar-Eintrag-ID. Einzige Label-Quelle —
  # sowohl der Sidebar-Render (sidebar_item) als auch der Vorlieben-Editor
  # nutzen sie, damit die Bezeichnungen konsistent bleiben.
  SIDEBAR_ITEM_LABEL_KEYS = {
    "dashboard"      => "nav.dashboard",
    "pinned"         => "shared.sidebar.pinned",
    "history"        => "shared.sidebar.history",
    "recent_topics"  => "shared.sidebar.recently_opened",
    "topics"         => "nav.topics",
    "inbox"          => "shared.sidebar.inbox",
    "tasks"          => "nav.tasks",
    "trash"          => "shared.sidebar.trash",
    "awaitings"      => "nav.waiting",
    "communications" => "nav.communications",
    "knowledge"      => "nav.knowledge",
    "persons"        => "nav.contacts",
    "times"          => "shared.sidebar.times",
    "calendar"       => "shared.sidebar.calendar",
    "documents"      => "shared.sidebar.documents",
    "sources"        => "shared.sidebar.sources",
    "docs"           => "shared.sidebar.docs",
    "tags"           => "shared.sidebar.tags"
  }.freeze

  def sidebar_item_label(id)
    key = SIDEBAR_ITEM_LABEL_KEYS[id.to_s]
    key ? t(key) : id.to_s
  end

  # id => Label-Map fuer den JS-Editor (Reset-Button baut die Listen neu auf).
  def sidebar_item_labels
    SIDEBAR_ITEM_LABEL_KEYS.keys.index_with { |id| sidebar_item_label(id) }
  end

  # #846: Einen Sidebar-Eintrag nach seiner ID rendern. Zentrale Registry,
  # damit Bereichszuordnung + Reihenfolge aus den Vorlieben (pref_sidebar_layout)
  # getrieben werden koennen. Unbekannte IDs => "" (robust gegen alte Layouts).
  def sidebar_item(id)
    case id.to_s
    when "dashboard"
      sidebar_link sidebar_item_label(id), dashboard_path, "gauge", reset_stack_id: "list:dashboard"
    when "pinned"
      sidebar_link sidebar_item_label(id), pinned_path, "pin", blade_kind: "list", blade_id: "pinned"
    when "history"
      sidebar_link sidebar_item_label(id), history_path, "history", blade_kind: "list", blade_id: "history"
    when "recent_topics"
      render "shared/sidebar_recent_topics"
    when "topics"
      sidebar_link sidebar_item_label(id), topics_path, "folder", blade_kind: "list", blade_id: "topics"
    when "inbox"
      sidebar_link sidebar_item_label(id), inbox_items_path, "inbox", blade_kind: "list", blade_id: "inbox_items"
    when "tasks"
      sidebar_link sidebar_item_label(id), tasks_path, "tasks", blade_kind: "list", blade_id: "tasks"
    when "trash"
      sidebar_link sidebar_item_label(id), trash_tasks_path, "trash"
    when "awaitings"
      render "shared/sidebar_awaitings"
    when "communications"
      sidebar_link sidebar_item_label(id), communications_path, "communications", blade_kind: "list", blade_id: "communications"
    when "knowledge"
      sidebar_link sidebar_item_label(id), knowledge_items_path, "knowledge", blade_kind: "list", blade_id: "knowledge_items"
    when "persons"
      sidebar_link sidebar_item_label(id), knowledge_items_path(stack: "list:persons"), "users", blade_kind: "list", blade_id: "persons"
    when "times"
      sidebar_link sidebar_item_label(id), time_entries_path, "timer", blade_kind: "list", blade_id: "time_entries"
    when "calendar"
      sidebar_link sidebar_item_label(id), calendar_path, "calendar", blade_kind: "list", blade_id: "calendar"
    when "documents"
      sidebar_link sidebar_item_label(id), documents_path, "file_text", blade_kind: "list", blade_id: "documents"
    when "sources"
      sidebar_link sidebar_item_label(id), sources_path, "quote", blade_kind: "list", blade_id: "sources"
    when "docs"
      sidebar_link sidebar_item_label(id), knowledge_items_path(item_type: "doc"), "manual"
    when "tags"
      sidebar_link sidebar_item_label(id), tags_path, "tag", blade_kind: "list", blade_id: "tags"
    else
      "".html_safe
    end
  end

  # Rendert ein Lucide-Icon. Die Partials in app/views/shared/icons/
  # enthalten NUR den inneren SVG-Inhalt (Pfade); der Helper baut die
  # einheitliche `<svg>`-Hülle drumherum — so steckt stroke-width und
  # Geometrie an genau einer Stelle.
  #
  #   icon "inbox"
  #   icon "chevron_right", size: "w-3.5 h-3.5", class: "transition-transform"
  #   icon "pencil", size: "w-4 h-4", stroke: 2
  # #417 (Hans, 2026-05-30): Tag-zu-Icon-Mapping. Setting-Key
  # `tag_icons` haelt eine JSON-Map {tag-name → lucide-icon-name}.
  # `tag_icon("idee")` gibt "lightbulb" zurueck oder nil, wenn kein
  # Mapping. `tag_icons_map` cached die geparste Map pro Request.
  def tag_icons_map
    @tag_icons_map ||= begin
      raw = Setting.get("tag_icons", default: "{}")
      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end
  end

  def tag_icon(tag_name)
    tag_icons_map[tag_name.to_s]
  end

  # #428 Phase 4 (Hans, 2026-05-31): Tag-Metadaten (Farbe/Beschreibung) aus
  # der zentralen Tag-Registry, pro Request gecached.
  TAG_PALETTE = %w[slate amber rose emerald sky violet].freeze

  def tag_meta_map
    @tag_meta_map ||= Tag.pluck(:name, :color, :description)
                         .to_h { |n, c, d| [n, { color: c, description: d }] }
  end

  def tag_description(tag_name)
    tag_meta_map.dig(tag_name.to_s, :description)
  end

  # Tailwind-Klassen (bg + text) fuer die Chip-Farbe eines Tags. Default
  # slate, wenn keine Farbe gesetzt.
  def tag_color_classes(tag_name)
    case tag_meta_map.dig(tag_name.to_s, :color)
    when "amber"   then "bg-amber-100 text-amber-800"
    when "rose"    then "bg-rose-100 text-rose-800"
    when "emerald" then "bg-emerald-100 text-emerald-800"
    when "sky"     then "bg-sky-100 text-sky-800"
    when "violet"  then "bg-violet-100 text-violet-800"
    else "bg-slate-100 text-slate-700"
    end
  end

  # Rendert ein Tag-Icon, wenn ein Mapping existiert UND das passende
  # Icon-Partial (`app/views/shared/icons/_<name>.html.erb`) vorhanden ist.
  # Sonst nil → Caller kann via `||` fallback rendern.
  def tag_icon_html(tag_name, **opts)
    name = tag_icon(tag_name)
    return nil unless name
    return nil unless lookup_context.template_exists?("shared/icons/_#{name}")
    icon(name, **opts)
  end

  # #705 (Hans): srcdoc-Inhalt für den HTML-Artefakt-iframe. Stellt dem
  # User-HTML ein kleines Resize-Skript voran, das die Inhaltshöhe an den
  # Parent postet (html-artifact-Controller setzt die iframe-Höhe). Das
  # eigentliche HTML bleibt unangetastet. Läuft im sandboxed iframe.
  def html_artifact_srcdoc(body)
    # #705 R2 (Hans): document.body (inhaltsgetrieben, NICHT an die iframe-
    # Höhe gekoppelt) messen + beobachten — sonst Feedback-Loop (iframe-Höhe
    # → documentElement.scrollHeight → iframe-Höhe → … wächst endlos).
    # Body-Zugriff bis DOMContentLoaded aufschieben — das Skript läuft am
    # Dokumentanfang, document.body existiert da noch nicht (sonst Throw).
    resize = '<script>(function(){function p(){try{if(!document.body)return;' \
             'parent.postMessage({__htmlArtifact:true,height:Math.max(' \
             'document.body.scrollHeight,document.body.offsetHeight)},"*")}catch(e){}}' \
             'function init(){if(window.ResizeObserver){new ResizeObserver(p).observe(document.body)}p()}' \
             'if(document.body){init()}else{document.addEventListener("DOMContentLoaded",init)}' \
             'window.addEventListener("load",p);setTimeout(p,400)})();</script>'
    resize + body.to_s
  end

  def icon(name, size: "w-5 h-5", stroke: 1.5, **html_options)
    extra_class = html_options.delete(:class)
    classes     = [size, extra_class].compact.join(" ").strip
    attrs = {
      xmlns:            "http://www.w3.org/2000/svg",
      viewBox:          "0 0 24 24",
      fill:             "none",
      stroke:           "currentColor",
      "stroke-width":   stroke,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      class:            classes,
      "aria-hidden":    "true"
    }.merge(html_options)
    inner = render("shared/icons/#{name}")
    content_tag(:svg, inner, attrs)
  end

  # Memoized pro Request: Org-Titel für das datalist-Autocomplete im
  # #533 1d: Minuten → „1:23 h" / „45 min".
  def format_minutes(mins)
    mins = mins.to_i
    h, m = mins.divmod(60)
    h.positive? ? "#{h}:#{format('%02d', m)} h" : "#{m} min"
  end

  # Kurzes Label des Inhaltsbezugs einer Zeitbuchung (Aufgabe/KI/Kommunikation).
  def time_entry_subject_label(entry)
    s = entry.subject
    return nil unless s
    case entry.subject_type
    when "Task"          then "##{s.id} #{s.title}"
    when "KnowledgeItem" then (s.display_label || s.title)
    when "Communication" then (s.try(:subject) || s.try(:title) || "Kommunikation")
    end
  end

  # Affiliations-Editor. Vorher wurde die Query pro Card neu gefeuert
  # (Stack-Mode mit N Persons → N×SELECT title FROM knowledge_items).
  def org_titles_for_datalist
    @org_titles_for_datalist ||=
      KnowledgeItem.organizations.order(:title).pluck(:title)
  end

  # #756 (Hans, 2026-06-23): viewport_frame_data entfernt — die Element-
  # Listen öffnen ihr Detail jetzt durchweg als Blade-Card im Stack
  # (blade-link), niemand nutzt den viewport-frame-Pfad mehr.

  # Freundliche Einzeiler für einen AuditLog-Eintrag an einer Task.
  # Beispiel: "Hans hat Status auf erledigt gesetzt"
  def audit_log_summary(log)
    actor_name = log.actor&.name || "Jemand"
    changes   = log.changes_data || {}

    case log.action
    when "created"
      "#{actor_name} hat die Aufgabe angelegt"
    when "destroyed"
      "#{actor_name} hat die Aufgabe gelöscht"
    when "updated"
      parts = changes.map do |attr, (from, to)|
        case attr
        when "status"
          "Status → #{t("tasks.status.#{to}", default: to.to_s)}"
        when "priority"
          "Priorität → #{t("tasks.priority.#{to}", default: to.to_s)}"
        when "assignee_id"
          who = to ? (Actor.find_by(id: to)&.name || "—") : "—"
          "Zugewiesen an → #{who}"
        when "due_date"
          "Fällig am → #{to || '—'}"
        when "follow_up_at"
          "Nachfassen am → #{to || '—'}"
        when "title"
          "Titel geändert"
        when "waiting_for"
          "Wartegrund geändert"
        when "published_at"
          # #411 Iter 2 (Hans, 2026-05-30): from→to-Uebergang als
          # Veroeffentlicht / Pausiert renderieren.
          to.nil? ? "Pausiert (Entwurf)" : "Veröffentlicht"
        else
          "#{attr} geändert"
        end
      end
      "#{actor_name}: #{parts.join(', ')}"
    else
      "#{actor_name}: #{log.action}"
    end
  end

  # Default-Prompt für die Chat-Sicherung. Editierbar via Setting
  # "chat_import_prompt" — gespeicherter Wert hat Vorrang. Wikilinks
  # bewusst NICHT erwähnt: der Chat kennt die anderen Knowledge-Items
  # nicht — Querverlinkung ist Aufgabe eines internen Agents später.
  #
  # #307 (Hans, 2026-05-23): Volltext-Dump statt Zusammenfassung,
  # plus Start- und End-Zeitstempel der Unterhaltung. Versionierung
  # ist im Inbox-Workflow ausgebaut — der Match-Key-Passus entfällt.
  CHAT_IMPORT_PROMPT_DEFAULT = <<~PROMPT.freeze
    Bitte schreibe den GESAMTEN bisherigen Chat als Markdown-Datei im
    folgenden Format. Antworte nur mit dem Markdown-Inhalt, kein
    Drumherum.

    ---
    title: <Titel dieses Chats, EXAKT wie er in der Chat-UI oben steht — denk dir nichts aus, übernimm wörtlich>
    type: note
    source_type: ai_conversation
    source_url: <URL dieses Chats, falls einsehbar>
    started_at: <ISO-8601-Datum/Uhrzeit der ERSTEN Nachricht in diesem Chat, so genau wie Du sie kennst>
    ended_at: <ISO-8601-Datum/Uhrzeit der LETZTEN Nachricht (= jetzt)>
    tags: [chat, <ggf. weitere Inhalts-Schlagworte — KEINE Themen/Projekte, einfach Begriffe>]
    ---

    # <gleicher Titel wie title oben>

    ## Verlauf

    <Vollständige Wiedergabe der Unterhaltung. Pro Nachricht ein Block:

      ### User (<Zeitstempel ISO-8601, soweit bekannt — sonst "—">)
      <Nachricht des Users wörtlich>

      ### Assistant (<Zeitstempel oder "—">)
      <Antwort des Assistant wörtlich>

    Reihenfolge wie im Chat. Keine Zusammenfassung, keine Kürzungen,
    keine Auslassungen. Code-Blöcke und Listen so übernehmen, wie sie
    im Chat erschienen sind. Anhänge/Bilder als "[Anhang: <Name oder
    Beschreibung>]" markieren.>
  PROMPT

  def chat_import_prompt
    Setting.get("chat_import_prompt", default: CHAT_IMPORT_PROMPT_DEFAULT)
  end

  # #672 (Hans, 2026-06-13): Auftrags-Vorlage für die Wikilink-Recherche
  # (🔍 an einem fehlenden Entitäts-Link, #655/#659). Editierbar in
  # Einstellungen → Wissens-Import. Platzhalter `{{title}}` (Entität),
  # `{{url}}` (Primär-Quelle), `{{source}}` (Quell-KI-Titel). Die
  # mechanischen Schluss-Zeilen (PATCH/Job-ID/done) hängt der Server an —
  # sie gehören nicht in die editierbare Prosa. „Knowledge-Item-Karte"
  # absichtlich vermieden: nicht jeder Item-Type ist eine KI-Karte; die
  # Feld-Vorgaben je Typ stehen im verlinkten Verfahren.
  WIKILINK_RESEARCH_PROMPT_DEFAULT = <<~PROMPT.freeze
    Recherche-Auftrag aus [[{{source}}]]

    Bitte einen passenden Wissens-Eintrag (KI) anlegen für **{{title}}** — Item-Type selbst wählen (Person / Organisation / Quelle / Notiz).

    Welche Felder je Item-Type zu füllen sind, steht im jeweiligen Verfahren: [[Verfahren: Entitäts-Recherche]] für Personen/Organisationen/Quellen, [[Verfahren: Recherche]] für Sachverhalte.

    Primär-Quelle: {{url}}
  PROMPT

  def wikilink_research_prompt
    Setting.get("wikilink_research_prompt", default: WIKILINK_RESEARCH_PROMPT_DEFAULT)
  end

  # Baut einen Turbo-Stream-Append, der einen Toast in den globalen
  # toast_stack einblendet. Wird von Controllern in Stream-Responses
  # mitgeschickt: `[..., toast_stream(...)]`.
  #
  # Beispiel:
  #   turbo_stream.replace(...) +
  #   helpers.toast_stream(message: "Thema entfernt",
  #                        undo_url: task_topics_path(...),
  #                        undo_payload: { topic_id: "bauamt" })
  def toast_stream(message:, undo_url: nil, undo_method: :post, undo_payload: {})
    turbo_stream.append("toast_stack",
      partial: "shared/toast",
      locals: { message: message, undo_url: undo_url,
                undo_method: undo_method, undo_payload: undo_payload })
  end

  # Toggle-Link für erledigte Aufgaben ausblenden/anzeigen.
  # Bewahrt alle bestehenden Query-Parameter; kippt nur show_done.
  def task_done_filter_link(show_done)
    q = request.query_parameters.dup
    if show_done
      q.delete("show_done")   # Default ist "ausblenden", darum Param ganz weg
      label = "Erledigte ausblenden"
    else
      q["show_done"] = "1"
      label = "Erledigte anzeigen"
    end
    href = q.empty? ? request.path : "#{request.path}?#{q.to_query}"
    link_to label, href, class: "text-xs text-slate-500 hover:text-slate-900 whitespace-nowrap"
  end

  # #619 Stufe 3: Übersetzungen für die JS-Schicht (Stimulus-Confirms/
  # Toasts/Fehler). Rendert window.MIO_I18N (flacher js.*-Namespace in der
  # aktuellen Locale) + window.t(key, vars) VOR den Controllern. window.t
  # fällt bei fehlendem Key auf den Key zurück (nie undefined).
  def js_i18n_tag
    payload = flatten_i18n_namespace("js", I18n.t("js", default: {}))
    # #757 (Hans, 2026-06-22): window.t akzeptiert Keys MIT und OHNE
    # `js.`-Präfix. Der Export flacht unter `js.<ns>.<key>` ab; viele
    # Controller (ui_inspector, cm6, diagnostic, stack_history, …) rufen aber
    # `window.t("<ns>.<key>")` ohne Präfix — seit der JS-i18n-Umstellung (#619
    # Stufe 3) lieferten die deshalb den ROHEN Key (z.B. „ui_inspector.region_
    # card" statt „Card"). Fallback auf `js.<key>` repariert alle auf einmal,
    # ohne bestehende `js.`-präfixte Aufrufe zu brechen.
    javascript_tag(
      "window.MIO_I18N=#{payload.to_json};" \
      "window.t=function(key,vars){var m=window.MIO_I18N||{};" \
      "var s=m[key]||m['js.'+key]||key;" \
      "if(vars){for(var k in vars){s=s.split('%{'+k+'}').join(vars[k]);}}return s;};"
    )
  end

  # #745: App-Version für die Anzeige (z.B. Footer der Einstellungen).
  # Quelle ist die VERSION-Datei via Miolimos::VERSION.
  def app_version
    Miolimos::VERSION
  end

  private

  def flatten_i18n_namespace(prefix, node, out = {})
    if node.is_a?(Hash)
      node.each { |k, v| flatten_i18n_namespace("#{prefix}.#{k}", v, out) }
    else
      out[prefix] = node.to_s
    end
    out
  end
end
