require "cgi"
require "redcarpet"
require "nokogiri"

# Stateless renderer für Knowledge-Item-Markdown. Verarbeitet `^abc`-
# Block-Anker, Obsidian-Wikilinks, Pandoc-Cites und externe Links.
#
# Pipeline:
#   1. normalize_list_indent — Tab/2-Space-Listen auf 4-Space anheben
#   2. ^anchor → <span data-anchor> Marker (überlebt Markdown-Render)
#   3. Redcarpet-Render zu HTML
#   4. inject_block_ids — Marker zu Block-IDs, Counter-Indicator anhängen
#   5. KnowledgeMarkdown::Wikilinks.resolve   — [[…]]   → <a class=wikilink>
#   6. KnowledgeMarkdown::Citations.resolve   — [@slug] → <a class=source-cite>
#   7. KnowledgeMarkdown::ExternalLinks.annotate — http(s)/mailto-Links
#
# #564: in vier Concerns zerlegt (reine Code-Moves) — diese Klasse hält nur
# noch den Pipeline-Durchlauf + Wikilink-Stash/Restore:
#   Highlights        — ==text==-Marks (#314…#543)
#   Embeds            — ![[Page]]-Einbettungen (#132)
#   ListPreprocessing — Listen/HR/juristische Gliederung (#500/#561)
#   Blocks            — Block-IDs + Backlink-Indikatoren (#341…#498)
class KnowledgeMarkdown
  include Highlights
  include Embeds
  include ListPreprocessing
  include Blocks

  # #617 v2: Render-Cache-Version — bei JEDER Aenderung an der Render-
  # Pipeline (Regex, Pass-Reihenfolge, Markup) hochzaehlen, sonst liefert
  # der kmd-Fragment-Cache (#578) bis zu 12h den alten Output (so geschehen
  # beim Highlight-Limit-Fix: Body unveraendert -> Key unveraendert).
  RENDER_CACHE_VERSION = 8

  ANCHOR_RE = /[ \t]+\^([a-z0-9][a-z0-9-]*)[ \t]*$/

  # #325 Phase 3b (Hans, 2026-05-25): `references_style` + `references_collector`.
  # Default `:inline` (Inline-Paren), `:footnote` macht Superscript-
  # Marker + (sofern kein Collector mitgegeben wird) eine Footnotes-
  # Sektion am Ende des HTML. WorkTreeRender reicht einen Collector
  # durch, damit ueber alle KI-Bodies hinweg eine einzige Footnote-
  # Liste am Ende der Render-Vorschau steht.
  def self.render(markdown, item: nil, references_style: :inline, references_collector: nil, highlight_filter: nil)
    # #578 (Hans-Go, 2026-06-11): Fragment-Cache fuer gerendertes HTML —
    # der teuerste Posten pro Request (Redcarpet+Nokogiri je Reply/KI).
    # Nur der Standardpfad wird gecacht (mit Item, ohne Collector/Filter);
    # Key = uuid + updated_at, dazu 12h-TTL als Frische-Backstop, weil
    # Querbezuege (Wikilink-Ziele, Backlinks) sich aendern koennen, ohne
    # dass das Item selbst angefasst wird (bewusster Trade-off, #578).
    cacheable = item&.persisted? && references_collector.nil? &&
                Array(highlight_filter).empty? && references_style == :inline
    if cacheable
      Rails.cache.fetch(["kmd", RENDER_CACHE_VERSION, item.uuid, item.updated_at.to_i], expires_in: 12.hours) do
        new(markdown, item: item,
            references_style: references_style,
            references_collector: references_collector,
            highlight_filter: highlight_filter).render
      end
    else
      new(markdown, item: item,
          references_style: references_style,
          references_collector: references_collector,
          highlight_filter: highlight_filter).render
    end
  end

  # #663 (Hans, 2026-06-13): Render-Cache eines Items gezielt verwerfen.
  # Nötig, wenn sich die BACKLINKS des Items ändern (ein anderes KI
  # verlinkt jetzt einen seiner Anker), ohne dass sein eigenes updated_at
  # wackelt — sonst zeigt die markierte Stelle bis zum 12h-TTL keinen
  # Backlink-Indikator auf das frische Rechercheergebnis.
  def self.bust_cache(item)
    return unless item&.persisted?
    Rails.cache.delete(["kmd", RENDER_CACHE_VERSION, item.uuid, item.updated_at.to_i])
  rescue => e
    Rails.logger.warn("KnowledgeMarkdown.bust_cache(#{item&.uuid}): #{e.class} #{e.message}")
  end

  def initialize(markdown, item: nil, embed_depth: 0, embed_stack: [], references_style: :inline, references_collector: nil, highlight_filter: nil)
    @markdown             = markdown.to_s
    @item                 = item
    @embed_depth          = embed_depth
    @embed_stack          = embed_stack  # UUIDs in der aktuellen Embed-Kette → Loop-Schutz
    @references_style     = references_style
    @references_collector = references_collector
    @highlight_filter     = Array(highlight_filter).map(&:to_s) & HIGHLIGHT_COLORS
  end

  def render
    # #500 (Hans, 2026-06-04): Leading-YAML-Frontmatter ist Metadaten, kein
    # Inhalt — vor dem Rendern entfernen, sonst erscheinen die Felder als
    # Absatz/Überschrift im Body (und verschieben die Block-Nummerierung).
    # KnowledgeBlockAnchor#block_line_indices ueberspringt das Frontmatter
    # ebenfalls, damit Render-Bloecke und Server-Anker ausgerichtet bleiben.
    md = strip_leading_frontmatter(@markdown)
    md = expand_embeds(md)
    md = convert_legal_enumerations(md)   # #561: (1)/a) -> Listen
    md = normalize_list_indent(md)
    md = ensure_blank_line_before_lists(md)
    md = ensure_blank_line_before_hr(md)
    md = md.gsub(ANCHOR_RE) { %( <span data-anchor="#{Regexp.last_match(1)}"></span>) }

    # #179: Wikilinks VOR Redcarpet zu Platzhaltern stempeln. Redcarpets
    # Autolink-Verhalten frisst sonst das erste `]` einer URL-haltigen
    # `[[Title|https://…]]`-Klammer und macht damit den Wikilink-Regex
    # nutzlos. Nach dem Redcarpet-Render ersetzen wir die Platzhalter
    # durch die aufgelösten Wikilink-Anker.
    md, wikilink_placeholders = stash_wikilinks(md)

    html = redcarpet.render(md)
    html = apply_legal_list_classes(html)   # #561
    backlink_data = @item ? backlink_data_for(@item) : {}
    html = inject_block_ids(html, backlink_data)
    html = apply_highlights(html, backlink_data)
    # #578: die Research-Job-Query braucht nur, wer auch Wikilinks hat —
    # vorher feuerte sie bei JEDEM Markdown-Render (z.B. pro Reply).
    jobs = wikilink_placeholders.any? ? jobs_by_title_for(@item) : {}
    html = restore_wikilinks(html, wikilink_placeholders, jobs_by_title: jobs)
    html = Citations.resolve(html)
    # #325 Phase 3b: `((Title))` als Footnote/Inline-Paren-Referenz.
    html = References.resolve(html, style: @references_style, collector: @references_collector)
    # #384 Phase 2 (Hans, 2026-05-27): @-Mentions auf App-Nutzer.
    html = ActorMentions.resolve(html)
    html = ExternalLinks.annotate(html)
    # #402 Phase C (Hans, 2026-05-28): Highlight-Filter — wenn aktiv,
    # zeigen wir NUR die `<mark>`-Texte der gewaehlten Farben,
    # getrennt durch `<hr>`. Reduziert die KI-Vorschau auf die
    # markierten Stellen.
    html = filter_highlights(html) if @highlight_filter.any?
    html
  end

  # Phase-A für #179: extrahiert alle [[…]]-Wikilinks und ersetzt sie
  # durch eindeutige Token-Strings. Token-Format `MIOLIMWIKILINK<i>END`
  # ist bewusst Single-Word ohne Sonderzeichen — Markdown rendert das
  # als Plain-Text und Redcarpets Autolink fasst es nicht an.
  # #672/#664-Folge (Hans, 2026-06-13): Code-Regionen vom Stashen
  # ausnehmen. Ein `[[@Name]]` in `inline-code` oder ```fenced``` soll
  # LITERAL stehen bleiben (Syntax-Beispiel), nicht zum Link werden —
  # sonst landet der `<a>` im `<code>` und der Text zerreißt. Gleiche
  # Logik wie strip_markdown_code (#496) bei den Highlights.
  CODE_SEGMENT_RE = /(```.*?```|~~~.*?~~~|`[^`\n]*`)/m

  def stash_wikilinks(md)
    placeholders = []
    # #466 (Hans, 2026-06-02): auch die Anker-only-Form `[[^id|alias]]`
    # stashen (zuerst, vor WIKILINK_RE), damit sie ueber Wikilinks.resolve
    # aufgeloest wird — sonst rendert Redcarpet sie als rohen Text.
    # #488 (Hans, 2026-06-04): Aufgaben-Referenz `[[#id]]` mitstashen, sonst
    # rendert Redcarpet sie als rohen Text (WIKILINK_RE matcht das `#` nicht).
    combined = Regexp.union(Wikilinks::ANCHOR_ONLY_RE, Wikilinks::TASK_REF_RE, Wikilinks::WIKILINK_RE)
    # split mit Capture-Gruppe → ungerade Indizes sind Code (unberuehrt).
    new_md = md.split(CODE_SEGMENT_RE).each_with_index.map do |chunk, idx|
      next chunk if idx.odd?
      chunk.gsub(combined) do
        i = placeholders.size
        placeholders << Regexp.last_match[0]
        "MIOLIMWIKILINK#{i}END"
      end
    end.join
    [new_md, placeholders]
  end

  # Phase-C für #179: ersetzt die Platzhalter im fertig gerenderten
  # HTML durch die aufgelösten Wikilink-Anker. #183: reicht source_item +
  # vorgemerkte Jobs an Wikilinks.resolve durch, damit pro Missing-Anker
  # ein 🔍 / ⏳ Indikator angezeigt werden kann.
  def restore_wikilinks(html, placeholders, jobs_by_title: {})
    placeholders.each_with_index do |original, i|
      html = html.sub("MIOLIMWIKILINK#{i}END",
                      Wikilinks.resolve(original,
                                        source_item: @item,
                                        jobs_by_title: jobs_by_title))
    end
    html
  end

  # #183: alle WikilinkResearchJobs der Quell-KI einmalig holen, indiziert
  # nach `target_title` (downcased), damit der Wikilink-Resolver pro
  # Missing-Anker ohne eigene Query auskommt.
  # #676 (Hans, 2026-06-13): nur Jobs mit noch existierendem Task ergeben
  # die ⏳-Sanduhr — sonst zeigt der Indikator auf einen gelöschten Task
  # (404). Ein verwaister Job (Task abgebrochen/gelöscht) fällt damit auf
  # den 🔍-Start-Indikator zurück, die Recherche lässt sich neu anstoßen.
  def jobs_by_title_for(item)
    return {} unless item
    WikilinkResearchJob
      .where(source_knowledge_item_id: item.uuid, target_knowledge_item_id: nil)
      .where(task_id: Task.select(:id))
      .index_by { |j| j.target_title.to_s.downcase }
  end

  private

  def redcarpet
    # #512 (Hans, 2026-06-04): no_intra_emphasis — sonst macht Redcarpet aus
    # Wort-internen Unterstrichen Emphasis (`bjork_1994_1` → bjork<em>1994</em>1).
    # Das zerschoss die neuen Citekey-Slugs in `[@slug]`-Zitaten (und Actor-/
    # Quellen-Slugs mit `_`). Wort-Rand-`_emphasis_` bleibt erhalten.
    @redcarpet ||= Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(hard_wrap: true, safe_links_only: true),
      fenced_code_blocks: true, tables: true, autolink: true, strikethrough: true,
      no_intra_emphasis: true
    )
  end
end
