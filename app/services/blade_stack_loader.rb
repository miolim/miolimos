# #163 Phase 5a-1: Parser fuer den ?stack=-Param. Versteht typisierte
# Tokens:
#
#   <uuid>          → KnowledgeItem (legacy, kein Prefix)
#   task:<id>       → Task
#   topic:<slug>    → Topic
#   src:<slug>      → Source
#
# Liefert geordnete Items mit allem, was der View braucht, um die Blade
# als initial-Card zu rendern (partial + locals). Reihenfolge entspricht
# dem Stack-Param. Nicht-existente IDs werden ausgelassen, kein Crash.
class BladeStackLoader
  # #350 (Hans, 2026-05-25): Item kann optional `meta` tragen — z.B.
  # `tab` fuer topic_list-Items, damit Tab-State im Stack-URL persistiert.
  Item = Struct.new(:kind, :id, :record, :meta, keyword_init: true) do
    # Per-Kind Render-Partial. Fuer :list wird das Partial pro list-Typ
    # ueber LIST_PARTIALS gemappt; record bleibt nil (Liste hat keine
    # einzelne Resource hinter sich).
    def partial
      return self.class::LIST_PARTIALS.fetch(id) if kind == :list
      self.class::PARTIALS.fetch(kind)
    end

    # Locals fuer das partial. body_html ist KI-spezifisch und wird nur
    # dort befuellt; der Helper baut die Map ueber bodies_for separat.
    def partial_locals
      case kind
      when :ki            then { item: record }
      when :task          then { task: record }
      when :topic         then { topic: record }
      when :topic_list    then { topic: record, tab: meta&.dig(:tab) }
      when :tag_list      then { tag: record }
      when :topic_render  then { topic: record }
      when :ki_refs       then { item: record }
      when :topic_refs    then { topic: record }
      when :source        then { source: record }
      when :awaiting      then { awaiting: record }
      when :communication then { communication: record }
      when :document      then { document: record }
      when :invoice       then { invoice: record }   # #926
      when :invoice_line  then { line: record }
      when :tree_focus    then { entry: record, focus: record }
      when :list          then {}  # Liste laedt ihre Daten selbst
      when :settings_page then { page: id, label: record }  # record = Label (#613)
      when :settings_sub  then { page: id.split(":", 2).first, sub: id.split(":", 2).last }
      when :inbox_item    then { item: record }  # #618
      end
    end

    # Hilfe fuer Controller: hat dieses list-Item Loader-Logik, die
    # ausserhalb von BladeStackLoader laufen muss (z.B. @tasks_for_blade
    # befuellen)?
    def list_kind
      kind == :list ? id : nil
    end

    # Stable-ID, die im DOM auf der Card landet (data-uuid). Fuer KIs
    # nutzen wir die rohe UUID (Legacy), fuer alle anderen den Prefix.
    def stack_uuid
      return record.uuid if kind == :ki
      # #247: topic_list nutzt im DOM `list:topic:<slug>`, konsistent mit
      # anderen Listen-Blades, in PREFIXES aber `topiclist:<slug>`.
      # #350: optional + `:tab` suffix fuer Tab-Persistenz.
      if kind == :topic_list
        suffix = meta&.dig(:tab).presence ? ":#{meta[:tab]}" : ""
        return "list:topic:#{id}#{suffix}"
      end
      # #418: tag_list nutzt DOM-uuid `list:tag:<name>`.
      return "list:tag:#{id}" if kind == :tag_list
      # #352: topic_render hat eine eigene DOM-uuid `render:topic:<slug>`.
      return "render:topic:#{id}" if kind == :topic_render
      # #343: ki_refs hat DOM-uuid `refs:ki:<uuid>`.
      return "refs:ki:#{id}"      if kind == :ki_refs
      # #352-follow: topic_refs hat DOM-uuid `refs:topic:<slug>`.
      return "refs:topic:#{id}"   if kind == :topic_refs
      "#{prefix}:#{id}"
    end

    # Prefix wie er im stack-Param vorkommt.
    def prefix
      case kind
      when :source       then "src"
      when :tree_focus   then "treefocus"
      when :list         then "list"
      when :topic_list   then "topiclist"
      when :topic_render then "topicrender"
      when :ki_refs      then "kirefs"
      when :topic_refs   then "topicrefs"
      when :invoice_line then "invoiceline"
      when :settings_page then "settings"   # #613
      when :settings_sub  then "settingssub" # #613 Stufe 2
      when :inbox_item    then "inboxitem"   # #618
      else                    kind.to_s
      end
    end
  end

  # Constants koennen nicht *innerhalb* eines Struct.new do…end-Blocks
  # auf die Struct-Klasse gelegt werden (sie wuerden in BladeStackLoader
  # selbst landen); deshalb assignen wir sie hier explizit auf Item.
  Item::PARTIALS = {
    ki:            "knowledge_items/stack_card",
    ki_refs:       "knowledge_items/refs_blade",
    task:          "tasks/blade_card",
    # #571: topic: rendert jetzt dasselbe Reiter-Blade wie topic_list —
    # das frühere Detail-Blade (topics/blade_card) war Legacy-Doppel-UI.
    topic:         "topics/index_list_blade",
    topic_list:    "topics/index_list_blade",
    tag_list:      "tags/list_blade",
    topic_render:  "topics/render_blade",
    topic_refs:    "topics/refs_blade",
    source:        "sources/stack_card",
    awaiting:      "awaitings/blade_card",
    communication: "communications/blade_card",
    document:      "documents/blade_card",
    invoice:       "invoices/blade_card",                 # #926
    invoice_line:  "invoices/invoice_line_blade_card",    # #541/#926
    tree_focus:    "tree_focus/blade",                    # #592 Z2
    settings_page: "settings/blades/card",                # #613
    settings_sub:  "settings/blades/sub_card",            # #613 Stufe 2
    inbox_item:    "inbox_items/blade_card"               # #618
  }.freeze

  Item::LIST_PARTIALS = {
    "tasks"          => "tasks/index_list_blade",  # #275: rich Variante
    "calendar"       => "calendar/list_blade",     # #573
    "awaitings"      => "awaitings/list_blade_card",
    "communications" => "communications/list_blade_card",
    "sources"        => "sources/list_blade_card",
    "inbox_items"    => "inbox_items/list_blade_card",
    "pinned"         => "knowledge_items/pinned_list_blade_card",
    "persons"        => "knowledge_items/persons_list_blade",
    "history"        => "history/list_blade_card",
    "time_entries"   => "time_entries/list_blade_card",  # #533 #5
    "documents"      => "documents/list_blade_card",      # #532
    "invoices"       => "invoices/list_blade_card",       # #926
    # Page-spezifische Listen-Blades — auf der jeweiligen Index-Seite
    # speziell behandelt (eigenes _index_list_blade-Partial inline).
    # Werden ueblicherweise nicht von Sidebar/Plus geladen, aber der
    # Eintrag macht den list:<key>-Token im URL-Stack-Param zulaessig.
    "dashboard"       => "dashboard/index_list_blade",
    "knowledge_items" => "knowledge_items/index_list_blade",
    # #163 Phase 6d: Topic-Show ist eine Blade-Stack-Seite mit der
    # list:topic-Card als Initial. Der konkrete @topic wird vom Aufrufer
    # (TopicsController#show) bereitgestellt; das Partial selber liest
    # ihn als @-Var.
    "topic"           => "topics/index_list_blade",
    # #613: Einstellungs-Liste (Einstieg des Settings-Stacks).
    "settings"        => "settings/index_list_blade",
    # #418 Iter 2 (Hans, 2026-05-30): Collection-Liste aller vergebenen
    # Tags. Klick auf einen Tag oeffnet das tag_list-Blade.
    "tags"            => "tags/tags_list_blade",
    # #435 (Hans, 2026-06-01): Collection-Liste aller Topics. Klick auf ein
    # Topic haengt dessen Listen-Blade an. Plural-Key "topics" — abgegrenzt
    # vom Singular "topic" (= Einzel-Topic-Show).
    "topics"          => "topics/topics_list_blade"
  }.freeze

  PREFIXES = {
    "task"          => :task,
    "topic"         => :topic,
    "topiclist"     => :topic_list,
    "treefocus"     => :tree_focus,
    "topicrender"   => :topic_render,
    "topicrefs"     => :topic_refs,
    "kirefs"        => :ki_refs,
    "taglist"       => :tag_list,
    "src"           => :source,
    "awaiting"      => :awaiting,
    "communication" => :communication,
    "document"      => :document,
    "invoice"       => :invoice,       # #926
    "invoiceline"   => :invoice_line,
    "settings"      => :settings_page,  # #613: Einstellungs-Seiten-Blade
    "settingssub"   => :settings_sub,    # #613 Stufe 2: Unterseiten-Blade
    "inboxitem"     => :inbox_item,      # #618: Inbox-Detail-Blade
    "list"          => :list
  }.freeze

  # Parst den stack-Param zu Items. Optimiert: pro Typ ein Bulk-Query,
  # nicht n+1.
  def self.parse(stack_param)
    return [] if stack_param.blank?
    tokens = stack_param.to_s.split(",").map(&:strip).reject(&:blank?)
    return [] if tokens.empty?

    by_kind = { ki: [], ki_refs: [], task: [], topic: [], topic_list: [], tag_list: [], topic_render: [], topic_refs: [], source: [], awaiting: [], communication: [], document: [], invoice: [], invoice_line: [], tree_focus: [], settings_page: [], settings_sub: [], inbox_item: [], list: [] }
    classified = tokens.map do |t|
      kind, id, meta =
        if t.start_with?("list:topic:")
          # #247: list:topic:<slug> wird als topic_list interpretiert.
          # data-uuid im DOM behaelt das "list:"-Praefix, damit Listen-
          # Blade-Selektoren matchen.
          # #350: optional `:tab`-Suffix fuer Tab-Persistenz —
          # `list:topic:<slug>:<tab>`.
          rest = t.sub(/\Alist:topic:/, "")
          if rest.include?(":")
            slug, tab = rest.split(":", 2)
            [:topic_list, slug, { tab: tab }]
          else
            [:topic_list, rest, nil]
          end
        elsif t.start_with?("list:tag:")
          # #418 (Hans, 2026-05-30): Tag-Listen-Blade.
          [:tag_list, t.sub(/\Alist:tag:/, ""), nil]
        elsif t.start_with?("render:topic:")
          # #352: render:topic:<slug> → topic_render (Rendering-Blade).
          rest = t.sub(/\Arender:topic:/, "")
          [:topic_render, rest, nil]
        elsif t.start_with?("refs:ki:")
          # #343: refs:ki:<uuid> → ki_refs (Reference-Blade).
          rest = t.sub(/\Arefs:ki:/, "")
          [:ki_refs, rest, nil]
        elsif t.start_with?("refs:topic:")
          # #352-follow: refs:topic:<slug> → topic_refs (Topic-Variante).
          rest = t.sub(/\Arefs:topic:/, "")
          [:topic_refs, rest, nil]
        elsif t.include?(":")
          prefix, rest = t.split(":", 2)
          k = PREFIXES[prefix]
          k ? [k, rest, nil] : nil
        else
          [:ki, t, nil]
        end
      next nil unless kind && id.present?
      by_kind[kind] << id
      [kind, id, meta]
    end

    # #602 S1: Blade-Lookups respektieren die Sichtbarkeit des aktuellen
    # Nutzers (Current.actor — im Web-Request immer gesetzt; Admins und
    # Agenten sind exempt). Unsichtbare Tokens fallen wie nicht-existente
    # IDs leise raus.
    actor = Current.actor
    records = {
      ki:            by_kind[:ki].any?            ? KnowledgeItem.visible_to(actor).where(uuid: by_kind[:ki]).index_by(&:uuid)                : {},
      ki_refs:       by_kind[:ki_refs].any?       ? KnowledgeItem.visible_to(actor).where(uuid: by_kind[:ki_refs]).index_by(&:uuid)           : {},
      topic_refs:    by_kind[:topic_refs].any?    ? Topic.visible_to(actor).where(slug: by_kind[:topic_refs]).index_by(&:slug)                : {},
      # #578: Task-Blades rendern das volle Detail (pickers/_summary liest
      # topics/attachments/predecessors/successors/subtasks/mentioned_kis/
      # sources) — dieselben Preloads wie TasksController#card, sonst
      # feuert jedes Task-Blade beim Stack-Restore ~8 Einzel-Queries.
      task:          by_kind[:task].any?          ? Task.visible_to(actor).includes(:topics, :attachments, :predecessors, :successors,
                                                                  :subtasks, :mentioned_kis, :sources)
                                                        .where(id: by_kind[:task]).index_by { |r| r.id.to_s }               : {},
      topic:         by_kind[:topic].any?         ? Topic.visible_to(actor).where(slug: by_kind[:topic]).index_by(&:slug)                     : {},
      topic_list:    by_kind[:topic_list].any?    ? Topic.visible_to(actor).where(slug: by_kind[:topic_list]).index_by(&:slug)                : {},
      topic_render:  by_kind[:topic_render].any?  ? Topic.visible_to(actor).where(slug: by_kind[:topic_render]).index_by(&:slug)              : {},
      source:        by_kind[:source].any?        ? Source.where(slug: by_kind[:source]).index_by(&:slug)                   : {},
      awaiting:      by_kind[:awaiting].any?      ? Awaiting.visible_to(actor).where(id: by_kind[:awaiting]).index_by { |r| r.id.to_s }       : {},
      communication: by_kind[:communication].any? ? Communication.visible_to(actor).where(id: by_kind[:communication]).index_by { |r| r.id.to_s } : {},
      document:      by_kind[:document].any?      ? Document.visible_to(actor).where(id: by_kind[:document]).index_by { |r| r.id.to_s }       : {},
      invoice:       by_kind[:invoice].any?       ? Invoice.visible_to(actor).where(id: by_kind[:invoice]).index_by { |r| r.id.to_s }         : {},
      invoice_line:  by_kind[:invoice_line].any?  ? InvoiceLine.where(id: by_kind[:invoice_line], invoice_id: Invoice.visible_to(actor).select(:id)).index_by { |r| r.id.to_s } : {},
      tree_focus:    by_kind[:tree_focus].any?    ? WorkNode.visible_to(actor).where(id: by_kind[:tree_focus]).index_by { |r| r.id.to_s }      : {},
      inbox_item:    by_kind[:inbox_item].any?    ? InboxItem.visible_to(actor).where(id: by_kind[:inbox_item]).index_by { |r| r.id.to_s }     : {}
    }

    classified.filter_map do |entry|
      next nil unless entry
      kind, id, meta = entry
      if kind == :list
        # Listen-Blades haben kein konkretes Record — wir akzeptieren sie,
        # sofern der id in LIST_PARTIALS bekannt ist (sonst lieber leise
        # ueberspringen als zur Render-Zeit zu crashen).
        next nil unless Item::LIST_PARTIALS.key?(id)
        Item.new(kind: :list, id: id, record: nil, meta: meta)
      elsif kind == :tag_list
        # #418: Tag hat kein DB-Model — record ist der Tag-Name selbst.
        Item.new(kind: :tag_list, id: id, record: id, meta: meta)
      elsif kind == :settings_page
        # #613: kein DB-Record — gegen die Seiten-Registry validieren;
        # record traegt das Anzeige-Label.
        spec = Settings::BladesController::PAGES[id]
        spec && Item.new(kind: :settings_page, id: id, record: spec[:label], meta: meta)
      elsif kind == :settings_sub
        # #613 Stufe 2: Seite muss bekannt sein; Existenz des Records
        # prüft das selbst-ladende Partial (verschwundene leise raus).
        page = id.split(":", 2).first
        Settings::BladesController::PAGES.key?(page) &&
          Item.new(kind: :settings_sub, id: id, record: id, meta: meta)
      else
        rec = records[kind][id]
        rec && Item.new(kind: kind, id: id, record: rec, meta: meta)
      end
    end
  end
end
