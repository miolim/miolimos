require "cgi"

# Resolver für Obsidian-Wikilinks. Aus knowledge_markdown.rb (#127)
# ausgelagert. Hängt nur am Lookup auf KnowledgeItem; alle
# Regex-/Render-Details bleiben hier lokal.
#
# Syntax:
#   [[Title]]                — Title- oder UUID-Lookup
#   [[Title#Heading]]        — Heading-Fragment
#   [[Title^anchor]]         — Block-Anchor-Fragment
#   [[Title|Alias]]          — angezeigter Text statt Title
#   [[Title|https://…]]      — Source-URL als Hinweis für späteres Entity-
#                              Import (#155). Display bleibt Title; das
#                              gerenderte <a> trägt data-source-url, das
#                              der Importer-Trigger (Hans) auswertet, um
#                              den Researcher mit Quelle-Kontext zu beauf-
#                              tragen.
class KnowledgeMarkdown
  module Wikilinks
    UUID_RE     = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    URL_RE      = /\Ahttps?:\/\//i
    # #692 (Hans): `[` aus der Titel-Klasse ausschließen — sonst matcht bei
    # geschachtelten/mehreren `[[` das WEITESTE Klammerpaar (das innere `[[`
    # landet sichtbar im Link). Mit `\[` ausgeschlossen greift das ENGSTE
    # `[[…]]`; ein vorangestelltes loses `[[` bleibt literaler Text.
    WIKILINK_RE = /\[\[([^\]|#\^\[]+)(?:#([^\]|]+))?(?:\^([^\]|]+))?(?:\|([^\]]+))?\]\]/
    # #387 Phase A.3 (Hans, 2026-05-28): Anker-only Wikilink
    # (`[[^abc12345]]`) — kein Title-Praefix. Aufgeloest via
    # KnowledgeItemAnchor-Lookup-Tabelle.
    # #466 (Hans, 2026-06-02): optionaler Alternate-Display nach dem Anker
    # (`[[^abc12345|Thread-Antwort]]`) — fuer Absatz-Links aus Antworten.
    # #466 (Hans, 2026-06-02): 8-Hex (Highlight) ODER 6-stellig
    # alphanumerisch (Block-Anker via ensure_anchor). 8-Hex zuerst, damit
    # ein 8-Hex-Anker nicht nur in seinen ersten 6 Zeichen gematcht wird.
    ANCHOR_ONLY_RE = /\[\[\^([a-f0-9]{8}|[a-z0-9]{6})(?:\|([^\]]+))?\]\]/.freeze

    # #488 (Hans, 2026-06-04): Aufgaben-Referenz `[[#435]]` → Link auf die
    # Aufgabe, gerendert als „#435 <Titel>". Optionaler Alias `[[#435|…]]`.
    # Eigene Form, weil WIKILINK_RE das `#` als Heading-Separator behandelt.
    TASK_REF_RE = /\[\[#(\d+)(?:\|([^\]]+))?\]\]/.freeze

    # #183: kleine Lucide-SVGs für die Per-Wikilink-Recherche-Indikatoren.
    SEARCH_ICON =
      %(<svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-3.5 h-3.5 align-middle" ) +
      %(viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">) +
      %(<circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>).freeze

    HOURGLASS_ICON =
      %(<svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-3.5 h-3.5 align-middle" ) +
      %(viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">) +
      %(<path d="M5 22h14"/><path d="M5 2h14"/><path d="M17 22v-4.172a2 2 0 0 0-.586-1.414L12 12l-4.414 4.414A2 2 0 0 0 7 17.828V22"/><path d="M7 2v4.172a2 2 0 0 0 .586 1.414L12 12l4.414-4.414A2 2 0 0 0 17 6.172V2"/></svg>).freeze

    module_function

    # `source_item` = die KI, in der dieser Wikilink steht; nötig, um den
    # WikilinkResearchJob anzulegen / zu prüfen. `jobs_by_title` ist eine
    # vorgemerkte Map (downcased Title → Job), die Aufrufer einmalig im
    # Render-Lauf befüllen, damit pro Wikilink keine eigene Query läuft.
    # #803 (aus #801 R4): resolve war eine 142-Zeilen-Methode — jetzt nur
    # noch der Dreiphasen-Ablauf; die Einzelfall-Logik liegt in
    # resolved_anchor_link / resolved_wikilink (+ deren Helfern) darunter.
    def resolve(html, source_item: nil, jobs_by_title: {})
      # #387 Phase A.3 (Hans, 2026-05-28): zuerst `[[^anchor]]` aufloesen.
      html = html.gsub(ANCHOR_ONLY_RE) do
        resolved_anchor_link(Regexp.last_match(1), Regexp.last_match(2).to_s.strip)
      end
      # #488 (Hans, 2026-06-04): Aufgaben-Referenz `[[#id]]` → Aufgaben-Link
      # „#id <Titel>". Vor WIKILINK_RE, da dort das `#` ausgeschlossen ist.
      html = html.gsub(TASK_REF_RE) do
        rendered_task(Regexp.last_match(1), Regexp.last_match(2).to_s.strip)
      end

      occurrence = 0
      html.gsub(WIKILINK_RE) do
        occurrence += 1
        resolved_wikilink(
          target_id:  Regexp.last_match(1).strip,
          heading:    Regexp.last_match(2),
          block_anch: Regexp.last_match(3),
          alias_raw:  Regexp.last_match(4),
          occurrence: occurrence, source_item: source_item, jobs_by_title: jobs_by_title
        )
      end
    end

    # Ein `[[^anchor]]`-Treffer: Anker in KI-/Task-Welt aufloesen und den
    # Stack-Link bauen (die Tabelle KnowledgeItemAnchor liefert die
    # zugehoerige KI-UUID, daraus wird der Link mit `#anchor`-Fragment).
    def resolved_anchor_link(anchor, alias_txt)
      display = alias_txt.presence || "^#{anchor}"
      row  = KnowledgeItemAnchor.find_by(anchor: anchor)
      item = row && KnowledgeItem.find_by(uuid: row.knowledge_item_uuid)
      # #480 Inc.3 (Hans, 2026-06-03): Anker, der in einer Task-Description
      # steht (Absatz-Link/Kommentar/Aufgabe), ueber TaskAnchor aufloesen —
      # der Link zeigt dann direkt auf den Task-Absatz.
      task_anchor = item.nil? ? TaskAnchor.find_by(anchor: anchor) : nil
      # `target_uuid` = die Stack-Card, in der der Anker liegt (Parent bei
      # Antworten). #490 (Hans, 2026-06-03): genau diese ID braucht der
      # blade-stack#openInStack, um eine SCHON offene Card zu fokussieren
      # + zum Anker zu scrollen, statt einen neuen Stack aufzumachen.
      href, ctx, target_uuid =
        if item
          # #466 (Hans, 2026-06-02): Liegt der Anker in einer ANTWORT, zeigt
          # der Link auf deren Parent (Aufgabe/KI) — der Absatz wird dort im
          # Replies-Bereich gerendert und per `#anchor`-Fragment angesteuert.
          if item.reply? && item.parent_type == "Task"
            ["/tasks?stack=task:#{item.parent_id_int}##{anchor}",
             "Antwort in Aufgabe ##{item.parent_id_int}",
             "task:#{item.parent_id_int}"]
          elsif item.reply? && item.parent_type == "KnowledgeItem"
            parent = KnowledgeItem.find_by(uuid: item.parent_uuid)
            ["/knowledge_items?stack=#{item.parent_uuid}##{anchor}",
             "Antwort in #{parent&.title}", item.parent_uuid]
          else
            ["/knowledge_items?stack=#{item.uuid}##{anchor}",
             "Anker in #{item.title}", item.uuid]
          end
        elsif task_anchor
          ["/tasks?stack=task:#{task_anchor.task_id}##{anchor}",
           "Anker in Aufgabe ##{task_anchor.task_id}",
           "task:#{task_anchor.task_id}"]
        end
      if href
        # #490: data-target-uuid/-anchor + openInStack -> schon offene Card
        # fokussieren & scrollen; sonst Card ans Stack-Ende anhaengen &
        # scrollen. href bleibt Fallback fuer Seiten ohne blade-stack.
        %(<a class="wikilink" href="#{href}" title="#{CGI.escapeHTML(ctx.to_s)}" ) +
          %(data-target-uuid="#{CGI.escapeHTML(target_uuid.to_s)}" ) +
          %(data-target-anchor="#{CGI.escapeHTML(anchor)}" ) +
          %(data-turbo-frame="_top" data-action="click->blade-stack#openInStack">) +
          CGI.escapeHTML(display) + "</a>"
      else
        %(<span class="wikilink wikilink-missing" title="Anker nicht gefunden">#{CGI.escapeHTML(display)}</span>)
      end
    end

    # Ein `[[…]]`-Treffer: getypte Praefixe (&Quelle, @Person), Relation-
    # Anker, Alias-/URL-Slot, dann Hit-/Miss-Rendering.
    def resolved_wikilink(target_id:, heading:, block_anch:, alias_raw:,
                          occurrence:, source_item:, jobs_by_title:)
      # #488 (Hans, 2026-06-03): getypte Praefixe im Wikilink.
      #   [[&slug]] / [[&Titel]] -> Quelle (Source), eigene Aufloesung.
      #   [[@Name]]              -> Personen-/Org-KI, optisch abgesetzt.
      prefix_alias = (alias_raw && alias_raw.strip !~ URL_RE) ? alias_raw.strip : nil
      if target_id.start_with?("&")
        key = target_id[1..].strip
        return rendered_source(key, prefix_alias.presence || key)
      elsif target_id.start_with?("@")
        name   = target_id[1..].strip
        person = lookup_person(name)
        # #655 v3: Miss als <a> wie rendered_miss — der nackte Span von
        # früher wurde von ActorMentions zerlegt („Kein App-Nutzer mit
        # Slug …"), und es fehlte der 🔍-Recherche-Einstieg.
        return rendered_person(person, prefix_alias.presence || name, block_anch) if person
        return rendered_miss(name, "@#{prefix_alias.presence || name}",
                             (source_item.try(:bib_source)&.url.presence || source_item.try(:source_url).presence),
                             source_item: source_item,
                             existing_job: jobs_by_title[name.downcase],
                             extra_class: "wikilink-person")
      end

      relation_anchor, block_anch = relation_anchor_for(block_anch, source_item)

      # Alias-Slot kann entweder Display-Text oder eine Source-URL sein.
      # URL hat Vorrang: Wenn https?://… → URL, Display fällt auf Title
      # zurück. Sonst wirkt's wie bisher als Display-Alias.
      if alias_raw && alias_raw.strip =~ URL_RE
        source_url = alias_raw.strip
        alias_text = nil
      else
        source_url = nil
        alias_text = alias_raw
      end

      target  = lookup_target(target_id)
      # Hinweis: `heading` ([[Titel#Überschrift]]) landete auch vorher nie
      # im Display — lookup_target clobberte Regexp.last_match(2) immer,
      # bevor das Join lief. Verhalten beibehalten: Alias vor Titel.
      display = (alias_text || target&.title || target_id).to_s.strip

      if target
        # #239 Phase B+: untyped Wikilinks bekommen ein „+"-Indicator
        # zum Auto-Typify. Bedingungen: kein Block-/Relation-Anchor schon
        # da, Quell-KI bekannt, sonst weiss der Server nicht, wo
        # nachzubessern.
        typifiable = relation_anchor.nil? && block_anch.nil? && source_item
        rendered_hit(target, block_anch, display, source_url,
                     relation_anchor: relation_anchor, source_item: source_item,
                     occurrence: occurrence, typifiable: typifiable)
      else
        rendered_miss(target_id, display, source_url,
                      source_item: source_item, existing_job: jobs_by_title[target_id.downcase])
      end
    end

    # #312 follow-up (Hans, 2026-05-23): Jeder `^id` ist eine Relation
    # (RelationSync legt sie pro Wikilink an). `target_block_anchor` auf der
    # Relation sagt, ob der Anker im Target-Body als Block existiert — dann
    # scrollt der Klick zum Absatz, unabhaengig vom Label-Status der Relation.
    # Liefert [relation_anchor, effektiver block_anchor]: Der Block-Anker
    # bleibt fuer den Scroll-Pfad nur erhalten, wenn die Relation ihn
    # explizit mit-traegt; sonst ist's eine reine source-zu-target-Relation.
    def relation_anchor_for(block_anch, source_item)
      return [nil, block_anch] unless block_anch.is_a?(String) &&
                                      block_anch =~ /\A[0-9a-z]{6}\z/ && source_item
      rel = Relation.find_by(source_uuid: source_item.uuid, anchor_id: block_anch)
      return [nil, block_anch] unless rel
      [block_anch, rel.target_block_anchor.presence]
    end

    def lookup_target(target_id)
      if target_id =~ UUID_RE
        KnowledgeItem.find_by(uuid: target_id.downcase)
      else
        # Title hat Vorrang vor Alias — eindeutige Title-Treffer sollen
        # nicht durch zufällige Alias-Kollision ausmaskiert werden.
        KnowledgeItem.by_title_ci(target_id).first ||
          KnowledgeItem.where("EXISTS (SELECT 1 FROM unnest(aliases) a WHERE LOWER(a) = ?)", target_id.downcase).first
      end
    end

    # #488 (Hans, 2026-06-03): Lookup auf Personen-/Org-KIs eingeschraenkt
    # (fuer [[@Name]]). Title hat Vorrang vor Alias.
    def lookup_person(name)
      scope = KnowledgeItem.where(item_type: %w[person organization])
      scope.by_title_ci(name).first ||
        scope.where("EXISTS (SELECT 1 FROM unnest(aliases) a WHERE LOWER(a) = ?)", name.downcase).first
    end

    # [[@Name]] -> Personen-KI-Link, violett abgesetzt + Personen-Marker.
    def rendered_person(target, display, block_anchor = nil)
      path = Rails.application.routes.url_helpers.knowledge_item_path(target.uuid)
      href = block_anchor ? "#{path}##{block_anchor}" : path
      anchor_attr = block_anchor ? %(data-target-anchor="#{CGI.escapeHTML(block_anchor)}" ) : ""
      %(<a href="#{href}" class="wikilink wikilink-person text-violet-700 underline" ) +
        %(data-target-uuid="#{target.uuid}" data-turbo-frame="_top" ) + anchor_attr +
        %(data-action="click->blade-stack#openInStack" title="Person: #{CGI.escapeHTML(target.title)}">) +
        "@" + CGI.escapeHTML(display) + "</a>"
    end

    # #488 (Hans, 2026-06-04): `[[#id]]` -> Aufgaben-Link, sky abgesetzt.
    # Display: Alias, sonst „#id <Titel>". Navigation in den Stack via
    # blade-stack#openInStack (target_uuid="task:<id>").
    def rendered_task(id, alias_txt = nil)
      task = Task.find_by(id: id)
      if task
        display = alias_txt.presence || "##{id} #{task.title}"
        %(<a class="wikilink wikilink-task text-sky-700 underline" href="/tasks?stack=task:#{id}" ) +
          %(data-target-uuid="task:#{id}" data-turbo-frame="_top" ) +
          %(data-action="click->blade-stack#openInStack" title="Aufgabe ##{id}: #{CGI.escapeHTML(task.title.to_s)}">) +
          CGI.escapeHTML(display) + "</a>"
      else
        %(<span class="wikilink wikilink-missing wikilink-task text-rose-600" ) +
          %(title="Aufgabe ##{id} nicht gefunden">##{CGI.escapeHTML(id.to_s)}</span>)
      end
    end

    # [[&slug]] / [[&Titel]] -> Quelle (Source). Lookup ueber slug, sonst
    # case-insensitive Title. Amber abgesetzt + Quellen-Marker. (Backlink-
    # Indexierung der Praefix-Links ist ein Folgeschritt — der Render ist
    # die sichtbare Funktion.)
    def rendered_source(key, display)
      source = Source.find_by(slug: key) ||
               Source.where("LOWER(title) = ?", key.downcase).first
      if source
        path = Rails.application.routes.url_helpers.source_path(source.slug)
        %(<a href="#{path}" class="wikilink wikilink-source text-amber-700 underline" ) +
          %(data-turbo-frame="_top" title="Quelle: #{CGI.escapeHTML(source.title.to_s)}">) +
          CGI.escapeHTML(display) + "</a>"
      else
        %(<span class="wikilink wikilink-missing wikilink-source text-rose-600" ) +
          %(title="Keine Quelle „#{CGI.escapeHTML(key)}"">#{CGI.escapeHTML(display)}</span>)
      end
    end

    def rendered_hit(target, block_anchor, display, source_url = nil,
                     relation_anchor: nil, source_item: nil,
                     occurrence: nil, typifiable: false)
      path = Rails.application.routes.url_helpers.knowledge_item_path(target.uuid)
      href = block_anchor ? "#{path}##{block_anchor}" : path
      anchor_attr = block_anchor ? %(data-target-anchor="#{CGI.escapeHTML(block_anchor)}" ) : ""
      url_attr    = source_url   ? %(data-source-url="#{CGI.escapeHTML(source_url)}" )    : ""
      relation_attr = relation_anchor ? %(data-relation-anchor="#{CGI.escapeHTML(relation_anchor)}" ) : ""
      # Typed Wikilinks: dotted underline statt solid, plus Popover-
      # Indicator-Icon. Stimulus-Controller `relation-popover` haengt
      # sich an die Indicator-Klicks (siehe Phase B).
      # #312 follow-up: Block-Anker-Wikilinks bleiben optisch solid
      # underlined (Absatz-Scroll-Verweis), auch wenn sie eine
      # Relation tragen. „Dotted" signalisiert nur die reine source-
      # zu-target-Relation ohne Absatzbezug.
      link_class = if relation_anchor && block_anchor.nil?
        "wikilink wikilink-typed text-emerald-700"
      else
        "wikilink text-emerald-700 underline"
      end
      # #365 Phase 2 (Hans, 2026-05-25): kein Inline-Indicator mehr
      # neben dem Wikilink — stattdessen Daten-Attribute am Wikilink,
      # die ein wikilink-hoover-Controller bei Hover in ein Float-
      # Popup UNTER dem Link rendert. Damit verschwindet der
      # Platzhalter-Space im Text.
      hoover_attrs = +""
      data_action  = +"click->blade-stack#openInStack"
      if relation_anchor && source_item
        hoover_attrs << %(data-controller="wikilink-hoover" )
        hoover_attrs << %(data-wikilink-hoover-kind-value="edit-relation" )
        hoover_attrs << %(data-wikilink-hoover-source-uuid-value="#{CGI.escapeHTML(source_item.uuid)}" )
        hoover_attrs << %(data-wikilink-hoover-anchor-id-value="#{CGI.escapeHTML(relation_anchor)}" )
        data_action << " mouseenter->wikilink-hoover#show mouseleave->wikilink-hoover#scheduleHide"
      elsif typifiable && source_item && occurrence
        hoover_attrs << %(data-controller="wikilink-hoover" )
        hoover_attrs << %(data-wikilink-hoover-kind-value="typify" )
        hoover_attrs << %(data-wikilink-hoover-source-uuid-value="#{CGI.escapeHTML(source_item.uuid)}" )
        hoover_attrs << %(data-wikilink-hoover-occurrence-value="#{occurrence}" )
        data_action << " mouseenter->wikilink-hoover#show mouseleave->wikilink-hoover#scheduleHide"
      end

      %(<a href="#{href}" class="#{link_class}" ) +
        %(data-target-uuid="#{target.uuid}" data-turbo-frame="_top" ) +
        anchor_attr + url_attr + relation_attr + hoover_attrs +
        %(data-action="#{data_action}">#{CGI.escapeHTML(display)}</a>)
    end

    # #239 Phase B: kleines „Beziehung bearbeiten"-Icon neben einem
    # typed Wikilink. Klick oeffnet den Inline-Popover.
    def relation_indicator(source_uuid, anchor_id)
      %(<a href="#" class="relation-link-indicator text-emerald-600 hover:text-emerald-800" ) +
        %(data-controller="relation-popover" ) +
        %(data-relation-popover-source-uuid-value="#{CGI.escapeHTML(source_uuid)}" ) +
        %(data-relation-popover-anchor-id-value="#{CGI.escapeHTML(anchor_id)}" ) +
        %(data-action="click->relation-popover#open" ) +
        %(title="Beziehung bearbeiten">) +
        RELATION_ICON + "</a>"
    end

    RELATION_ICON =
      %(<svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-3 h-3 align-middle" ) +
      %(viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">) +
      %(<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>) +
      %(<path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>).freeze

    # #239 Phase B+: „+"-Icon zum Auto-Typify eines untyped Wikilinks.
    # Klick triggert POST /knowledge_items/:source/wikilink_typify mit
    # occurrence — Server fuegt ^anchor_id ein und liefert anchor zurueck;
    # der Stimulus-Controller laedt dann sofort den Relation-Popover.
    def typify_indicator(source_uuid, occurrence)
      %(<a href="#" class="relation-typify-indicator text-slate-300 hover:text-emerald-600" ) +
        %(data-controller="relation-typify" ) +
        %(data-relation-typify-source-uuid-value="#{CGI.escapeHTML(source_uuid)}" ) +
        %(data-relation-typify-occurrence-value="#{occurrence}" ) +
        %(data-action="click->relation-typify#start" ) +
        %(title="Beziehung qualifizieren">) +
        TYPIFY_ICON + "</a>"
    end

    TYPIFY_ICON =
      %(<svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-3 h-3 align-middle" ) +
      %(viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">) +
      %(<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>).freeze

    # #183: Bei Missing-Anker kann ein per-Wikilink-Researcher-Trigger
    # angehängt werden — sichtbar als 🔍 (kein Job) oder ⏳ (läuft).
    # Voraussetzungen:
    #   - source_item gesetzt (sonst weiß die Action nicht, in welcher
    #     Quell-KI der Wikilink steht)
    #   - source_url vorhanden (ohne URL hat der Researcher keinen
    #     Startpunkt für die Recherche)
    def rendered_miss(target_id, display, source_url = nil, source_item: nil, existing_job: nil, extra_class: nil)
      url_attr   = source_url ? %(data-source-url="#{CGI.escapeHTML(source_url)}" ) : ""
      title_attr = source_url ? %(title="Fehlende Entität — Quelle: #{CGI.escapeHTML(source_url)}") :
                                 %(title="Klicken, um diese Notiz anzulegen")
      # #184: missing-Anker hat href="#" — auf einer Comment-Frame-Seite
      # ohne blade-stack-Controller würde der Default-Click die Seite
      # neu laden. Frame-Bust via data-turbo-frame="_top" verhindert,
      # dass Turbo den href="#" als Navigation interpretiert.
      anchor = %(<a href="#" class="wikilink wikilink-missing#{extra_class ? " #{extra_class}" : ""} text-rose-600" ) +
               %(data-target-title="#{CGI.escapeHTML(target_id)}" data-turbo-frame="_top" ) +
               url_attr +
               %(data-action="click->blade-stack#openMissing" ) +
               title_attr + ">" +
               CGI.escapeHTML(display) +
               "</a>"

      indicator = research_indicator(target_id, source_url, source_item, existing_job)
      indicator.empty? ? anchor : %(<span class="inline-flex items-center gap-0.5">#{anchor}#{indicator}</span>)
    end

    # 🔍 wenn kein Job (Klick startet Recherche), ⏳ wenn Job läuft
    # (Link zum Task), nichts wenn weder Source-URL noch Quell-KI da.
    def research_indicator(target_id, source_url, source_item, existing_job)
      return "" if source_item.nil? || source_url.nil?

      if existing_job
        task_path = Rails.application.routes.url_helpers.task_path(existing_job.task_id)
        %(<a href="#{task_path}" class="wikilink-research-pending text-amber-600 hover:text-amber-700" ) +
          %(data-turbo-frame="_top" target="_blank" ) +
          %(title="Recherche läuft (Task ##{existing_job.task_id})">) +
          HOURGLASS_ICON + "</a>"
      else
        %(<a href="#" class="wikilink-research-start text-emerald-600 hover:text-emerald-700" ) +
          %(data-controller="wikilink-research" ) +
          %(data-action="click->wikilink-research#start" ) +
          %(data-wikilink-research-source-uuid-value="#{CGI.escapeHTML(source_item.uuid)}" ) +
          %(data-wikilink-research-target-title-value="#{CGI.escapeHTML(target_id)}" ) +
          %(data-wikilink-research-target-source-url-value="#{CGI.escapeHTML(source_url)}" ) +
          %(title="Recherche starten">) +
          SEARCH_ICON + "</a>"
      end
    end
  end
end
