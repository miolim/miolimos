# #203 Phase E.6: Inline-Markdown-Rendering fuer Task-Kommentare.
module MarkdownHelper
  # Schmales Markdown-Rendering für freie Text-Felder (Task-Kommentare,
  # später ggf. weitere). Bewusst minimal: kein HTML-Filter raw, kein
  # Inline-HTML — wir rendern Plain-Markdown und sanitisieren das
  # Ergebnis mit dem Standard-Sanitizer von Rails.
  #
  # `hilfe_marker: true` (#1677) schaltet die Hilfe-Marker ein — siehe
  # hilfe_marker_ersetzen. Bewusst nur auf Wunsch: In Aufgaben, Antworten und
  # Wissenseinträgen bleibt `:ui:xyz:` schlichter Text.
  def render_inline_markdown(text, item: nil, highlight_filter: nil, hilfe_marker: false)
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
    # #1677: Marker NACH dem Sanitizer, der <svg> sonst entfernte (dasselbe
    # Verfahren wie bei den Backlink-Indikatoren).
    clean = hilfe_marker_ersetzen(clean) if hilfe_marker
    clean
  end

  # #1677 (aus immoOS #1658 übernommen; Hans dort): „Könnten die Icons im
  # Programm alle eine ID bekommen? … Die ID kennzeichnet den Icon-Ort."
  #
  #   `:ui:karte_schliessen:`  → Symbol des Bedienelements (folgt dem Programm)
  #   `:icon:flame:`           → schlichtes Symbol
  #   `:feld:<schlüssel>:`     → aktuelle Feldbeschriftung, fett
  #   `:bereich:<schlüssel>:`  → Abschnittsbeschriftung, fett und kursiv
  #
  # Unbekanntes bleibt als Text stehen: Ein Tippfehler soll sichtbar sein und
  # nicht spurlos verschwinden.
  #
  # Zwei Abweichungen vom Fork, beide bewusst: (1) nur auf Wunsch (oben), und
  # (2) ersetzt wird NUR IN TEXTKNOTEN außerhalb von <code>/<pre>. Der Fork
  # ersetzte per gsub im fertigen HTML — ein Marker in einem Link-Ziel oder in
  # einem Code-Beispiel zerbrach dort das Markup bzw. das Beispiel.
  ICON_MARKER_RE = /:(ui|icon):([a-z0-9_-]{1,60}):/
  TEXT_MARKER_RE = /:(feld|bereich):([a-z0-9_.]{1,80}):/
  HILFE_MARKER_RE = Regexp.union(ICON_MARKER_RE, TEXT_MARKER_RE)
  private_constant :ICON_MARKER_RE, :TEXT_MARKER_RE, :HILFE_MARKER_RE

  def hilfe_marker_ersetzen(html)
    return html if html.blank? || !html.include?(":")

    fragment = Nokogiri::HTML5.fragment(html)
    fragment.xpath(".//text()[not(ancestor::code) and not(ancestor::pre)]").each do |knoten|
      next unless knoten.content.match?(HILFE_MARKER_RE)

      neu = ERB::Util.html_escape(knoten.content).gsub(HILFE_MARKER_RE) { |marker| hilfe_marker_html(marker) || marker }
      knoten.replace(Nokogiri::HTML5.fragment(neu))
    end
    fragment.to_html.html_safe
  end

  def hilfe_marker_html(marker)
    if (m = ICON_MARKER_RE.match(marker))
      art, schluessel = m[1], m[2]
      name  = art == "ui" ? UiElemente.icon_fuer(schluessel) : schluessel
      return nil unless name && icon_vorhanden?(name)

      titel = art == "ui" && UiElemente[schluessel] ? t(UiElemente[schluessel][:label], default: schluessel) : nil
      # Farbe aus .hilfe-bezeichnung (eine Stelle für alles); -0.125em setzt das
      # Symbol auf die Mittellinie der Schrift statt auf die Grundlinie.
      icon(name, size: "w-[1.15em] h-[1.15em]",
           class: "hilfe-bezeichnung hilfe-symbol hilfe-zeigbar inline-block align-[-0.125em] mx-0.5",
           "data-hilfe-art": art, "data-hilfe-schluessel": schluessel,
           **(titel ? { title: titel } : {})).to_s
    elsif (m = TEXT_MARKER_RE.match(marker))
      art, schluessel = m[1], m[2]
      text = I18nBeschriftungen.text(schluessel)
      return nil if text.blank?

      # Der Marker trägt sein Ziel; das Suchen übernimmt der hilfe-zeiger-Controller.
      sicher = ERB::Util.html_escape(text)
      ziel   = %(data-hilfe-art="#{art}" data-hilfe-schluessel="#{ERB::Util.html_escape(schluessel)}")
      if art == "bereich"
        %(<strong class="hilfe-bezeichnung hilfe-bereich hilfe-zeigbar" #{ziel}><em>#{sicher}</em></strong>)
      else
        %(<strong class="hilfe-bezeichnung hilfe-feld hilfe-zeigbar" #{ziel}>#{sicher}</strong>)
      end
    end
  end

  def icon_vorhanden?(name)
    return false unless name.to_s.match?(/\A[a-z0-9_-]{1,60}\z/)

    @icon_vorhanden ||= {}
    @icon_vorhanden.fetch(name) do
      @icon_vorhanden[name] = Rails.root.join("app/views/shared/icons/_#{name}.html.erb").exist?
    end
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
