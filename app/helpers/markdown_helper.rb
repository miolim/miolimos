# #203 Phase E.6: Inline-Markdown-Rendering fuer Task-Kommentare.
module MarkdownHelper
  # Schmales Markdown-Rendering für freie Text-Felder (Task-Kommentare,
  # später ggf. weitere). Bewusst minimal: kein HTML-Filter raw, kein
  # Inline-HTML — wir rendern Plain-Markdown und sanitisieren das
  # Ergebnis mit dem Standard-Sanitizer von Rails.
  def render_inline_markdown(text, item: nil, highlight_filter: nil)
    return "".html_safe if text.blank?
    @inline_md_renderer ||= Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(filter_html: true, no_styles: true,
                                  hard_wrap: true,
                                  link_attributes: { target: "_blank", rel: "noopener noreferrer" }),
      autolink: true, fenced_code_blocks: true, no_intra_emphasis: true,
      strikethrough: true, tables: true
    )
    # #179: Wikilinks vor Redcarpet zu Platzhaltern stempeln — sonst frisst
    # Redcarpets Autolink den ersten ] einer URL-haltigen Wikilink-Klammer.
    placeholders = []
    # #466 (Hans, 2026-06-02): auch Anker-only `[[^id|alias]]` stashen,
    # damit ein in eine Antwort/einen Kommentar eingefuegter Anker-Link
    # ueber Wikilinks.resolve aufgeloest wird (sonst roher Text).
    wl_re = Regexp.union(KnowledgeMarkdown::Wikilinks::ANCHOR_ONLY_RE,
                         KnowledgeMarkdown::Wikilinks::WIKILINK_RE)
    md = text.to_s.gsub(wl_re) do
      i = placeholders.size
      placeholders << Regexp.last_match[0]
      "MIOLIMWIKILINK#{i}END"
    end
    html = @inline_md_renderer.render(md)
    placeholders.each_with_index do |original, i|
      html = html.sub("MIOLIMWIKILINK#{i}END",
                      KnowledgeMarkdown::Wikilinks.resolve(original))
    end
    # #384 Phase 3a-Fix (Hans, 2026-05-27): @-Mentions auch im Inline-
    # Render aufloesen (Task-Comments, Reply-KIs etc.).
    html = KnowledgeMarkdown::ActorMentions.resolve(html)
    # #450 (Hans, 2026-06-01): Highlights (`==farbe|text==`) als <mark>
    # rendern — bisher kannte der Inline-Renderer (Replies/Task-Kommentare)
    # sie nicht. Mit highlight_filter auf die passenden Marks reduzieren;
    # nil = der Reply hat keine passende Mark -> Caller blendet ihn aus.
    html = KnowledgeMarkdown.apply_highlights_to(html, filter: highlight_filter)
    return "".html_safe if html.nil?
    # #465/#466 (Hans, 2026-06-02): block-N-IDs auf die Absatz-Bloecke
    # setzen — paragraph-actions braucht sie, um Hover-Markierung +
    # Kontextmenue an einen Absatz zu haengen (auch in Antworten).
    # Beim gefilterten Render (highlight_filter) lassen wir es: dort
    # stehen nur Mark-Fragmente, keine ankerbaren Absaetze.
    html = KnowledgeMarkdown.assign_block_ids(html) if highlight_filter.blank?
    # #184: data-turbo-frame und data-action erlauben, sonst entfernt
    # der Sanitizer den Frame-Bust und die blade-stack-Action-Direktive
    # vom Wikilink-Anker.
    # #384: `span` + `data-actor-id` erlauben, damit der ActorMention-Pill
    # nicht weggefiltert wird.
    # #450: `mark` + `id` erlauben, damit die Highlight-Marks (mit
    # optionalem Anker-id) ueberleben.
    clean = sanitize html,
             tags: %w[p br strong em del code pre ul ol li a span mark blockquote h1 h2 h3 h4 h5 h6 table thead tbody tr th td],
             attributes: %w[href target rel class id data-source-url data-turbo-frame data-action data-target-uuid data-target-title data-target-anchor data-actor-id title]
    # #475 (Hans, 2026-06-02): Backlink-Indikatoren NACH dem Sanitize
    # injizieren (trusted, app-generiertes HTML mit <svg> + data-attrs, die
    # der Sanitizer sonst entfernt). Nur im ungefilterten Voll-Render und
    # wenn das Quell-Item bekannt ist (z.B. die Reply-KI).
    if highlight_filter.blank? && item
      clean = KnowledgeMarkdown.inject_backlink_indicators_for(clean, item).html_safe
    end
    clean
  end

  # #450 (Hans, 2026-06-01): Highlight-Counts pro Farbe fuer das Filter-UI
  # der KI-Detail-Section — aus der UNGEFILTERTEN Beschreibung PLUS allen
  # Reply-Bodies. Dadurch (a) bleiben die Farb-Chips stehen, wenn ein
  # Filter aktiv ist (sonst wuerden die anderen Farben auf 0 fallen und
  # verschwinden), und (b) zaehlen Highlights in Antworten mit.
  # Liefert {color => count}, nur Farben mit count > 0.
  def knowledge_highlight_counts(item)
    counts = Hash.new(0)
    begin
      body = FileProxy.read_body(actor: current_actor, knowledge_item: item)
      KnowledgeMarkdown.highlight_counts(body).each { |c, n| counts[c] += n }
    rescue StandardError
      # Binär-Attachment (PDF etc.) oder fehlende Datei -> keine Body-Highlights.
    end
    KnowledgeItem.replies_for(item, viewer: current_actor).each do |reply|
      KnowledgeMarkdown.highlight_counts(reply.body).each { |c, n| counts[c] += n }
    end
    # In kanonischer Farb-Reihenfolge zurueckgeben (stabile Chip-Reihenfolge).
    KnowledgeMarkdown::HIGHLIGHT_COLORS.each_with_object({}) do |color, h|
      h[color] = counts[color] if counts[color] > 0
    end
  end
end
