# #365 Phase 3 (Hans, 2026-05-25): Wraps a block (or a substring
# within a block) of a KI body in `==color text==`-Highlight-Markup.
# Persistierte Aenderung im Markdown-File (FileProxy). Nutzt
# KnowledgeBlockAnchor.block_line_indices, um den richtigen Block in
# der Source zu finden.
class BodyHighlightWrapper
  COLORS = %w[gelb rot gruen blau lila].freeze
  # #365 follow (Hans, 2026-05-25 21:36): special-color "keine" =
  # unwrap-only — entfernt existierende `==color|...==`-Wraps im Block
  # bzw. um den Selected-Text, ohne neuen Wrap zu setzen.
  UNWRAP_TOKEN = "keine".freeze

  # #449 (Hans, 2026-06-01): Block-Marker am Zeilenanfang (Listen-
  # Bullet, nummerierte Liste, Blockquote, Heading) muessen beim
  # Whole-Block-Wrap AUSSERHALB der `==color|...==`-Klammer bleiben.
  # Sonst wandert z.B. das `- ` mit in den Highlight
  # (`==gelb|- foo==`), die Zeile beginnt nicht mehr mit einem Listen-
  # Marker, und der Markdown-Renderer macht aus dem Listenpunkt einen
  # Absatz mit literalem „-" ohne Einrueckung. Wir ziehen einen
  # optionalen fuehrenden Marker (inkl. Einrueckung) ab und wrappen nur
  # den Rest dahinter.
  BLOCK_PREFIX_RE = /\A([ \t]*(?:[-*+] |\d+[.)] |>+ |\#{1,6} ))/

  # #475 (Hans, 2026-06-02): Anker-Muster — 8-Hex (Highlight) ODER
  # 6-stellig alphanumerisch (Block-Anker, ensure_anchor). Nach der
  # Anker-Vereinheitlichung (#466) muessen die Highlight-Regexe beide
  # akzeptieren, sonst rendert ein 6-stelliger Anker am Highlight als
  # roher Text und laesst sich nicht mehr ent-/umwrappen.
  ANCHOR_PAT = '(?:[a-f0-9]{8}|[a-z0-9]{6})'.freeze
  # Nackter Block-Anker am Block-Ende (z.B. `… Satz ^abc123`). Wird beim
  # Wrap aus dem Text gezogen, sonst landet er SICHTBAR im Highlight.
  TRAILING_ANCHOR_RE = /\s+\^(#{ANCHOR_PAT})\s*\z/m.freeze

  class Error < StandardError; end

  # #469 (Hans, 2026-06-02): der beim Wrap gesetzte (oder wieder-
  # verwendete) 8-Hex-Anker — damit der Caller (Selektions-Menue) das
  # frische Highlight praezise verlinken/kommentieren/vertasken kann.
  attr_reader :result_anchor

  def self.call(item:, actor:, anchor:, color:, selected_text: nil)
    new(item: item, actor: actor, anchor: anchor, color: color,
        selected_text: selected_text).call
  end

  def initialize(item:, actor:, anchor:, color:, selected_text:)
    @item          = item
    @actor         = actor
    @anchor        = anchor.to_s.strip
    @color         = color.to_s.strip.downcase
    # #365 (Hans, 2026-05-28): Leading/trailing whitespace defensiv
    # entfernen, sonst landet ein Leerzeichen am Anfang im
    # `==color| Text==`-Wrap und ist im gerenderten <mark> sichtbar.
    @selected_text = selected_text.to_s.strip
    raise Error, "ungueltige Farbe" unless COLORS.include?(@color) || @color == UNWRAP_TOKEN
    raise Error, "kein Anker" if @anchor.empty?
  end

  def call
    body = read_body
    raise Error, "Body leer" if body.nil? || body.empty?
    block_lines =
      if @selected_text.present?
        locate_block_for_selection(body)
      else
        locate_block(body)
      end
    raise Error, "Block nicht gefunden" unless block_lines

    new_body =
      if @selected_text.present?
        wrap_substring(body, block_lines)
      else
        wrap_whole_block(body, block_lines)
      end

    write_body(new_body)
    new_body
  end

  private

  # Index (0-basiert) des Blocks, der zum gegebenen Anker passt — oder nil.
  # Anker-Format:
  #   - `block-N` → N-ter (1-basiert) Block in der Source
  #   - `<id>`    → Block, dessen letzte Zeile mit `^<id>` markiert ist
  def anchor_block_index(anchor_blocks, body)
    if @anchor =~ /\Ablock-(\d+)\z/i
      n = Regexp.last_match(1).to_i - 1
      return n if n >= 0 && n < anchor_blocks.size
    else
      anchor_blocks.each_index do |i|
        lines = anchor_blocks[i].map { |j| body.lines[j] }.join
        return i if lines.match?(/\^#{Regexp.escape(@anchor)}(\s|$)/)
      end
    end
    nil
  end

  # Findet die Line-Indizes des Blocks, der zum gegebenen Anker passt.
  def locate_block(body)
    anchor_blocks = KnowledgeBlockAnchor.new(@item, actor: @actor).send(:block_line_indices, body)
    idx = anchor_block_index(anchor_blocks, body)
    idx ? anchor_blocks[idx] : nil
  end

  # #684 (Hans, 2026-06-13): Block für eine SUBSTRING-Selektion bestimmen —
  # robust gegen Block-Nummerierungs-Drift. Der Frontend schickt als Anker
  # die gerenderte DOM-Block-Nr (inject_block_ids), die Source-Suche nutzt
  # block_line_indices. Beide zählen i.d.R. 1:1, aber ein Element, das
  # gerendert KEINE block-id bekommt (z.B. ein `<hr>`/Trenner), wird in der
  # Source mitgezählt → ab da sind die DOM-Nummern um 1 versetzt und der
  # Anker-Block enthält die Selektion nicht ("Selektion im Block nicht
  # gefunden"). Fix: zuerst den Anker-Block prüfen; enthält er die
  # Selektion nicht, den Block per INHALT suchen — bei mehreren Treffern
  # den, der dem Anker-Index am nächsten liegt (kleine Drift ist die Regel).
  def locate_block_for_selection(body)
    anchor_blocks = KnowledgeBlockAnchor.new(@item, actor: @actor).send(:block_line_indices, body)
    primary = anchor_block_index(anchor_blocks, body)
    return anchor_blocks[primary] if primary && block_contains_needle?(anchor_blocks[primary], body)

    candidates = anchor_blocks.each_index.select { |i| block_contains_needle?(anchor_blocks[i], body) }
    # Nichts per Inhalt gefunden → den Anker-Block zurückgeben, damit
    # wrap_substring den präzisen "nicht gefunden"-Fehler werfen kann.
    return anchor_blocks[primary] if candidates.empty? && primary
    return nil if candidates.empty?
    best = primary ? candidates.min_by { |i| (i - primary).abs } : candidates.first
    anchor_blocks[best]
  end

  # Enthält der Block (line-indices) die aktuelle Selektion — exakt oder
  # markup-tolerant (nach Abstreifen bestehender `==…==`-Wraps)?
  def block_contains_needle?(idxs, body)
    bt = idxs.map { |i| body.lines[i] }.join
    cleaned, = strip_existing_wrap(bt)
    cleaned.include?(@selected_text) || !markup_tolerant_span(cleaned, @selected_text).nil?
  end

  def wrap_whole_block(body, block_lines)
    lines = body.lines
    first = block_lines.first
    last  = block_lines.last
    block_text = lines[first..last].join
    # Trailing-Whitespace abtrennen, damit `==` direkt an die Inhalts-
    # Grenzen kommt (HIGHLIGHT_RE matched `==(?!\s)` — kein Leerzeichen
    # direkt nach den `==`).
    trailing_ws = block_text[/\s*\z/]
    core        = block_text.chomp(trailing_ws.to_s)
    # #387 Phase A (Hans, 2026-05-28): Beim Re-Wrap (Color-Change) den
    # bestehenden Anker mit-uebernehmen, damit externe Links nicht
    # brechen. strip_existing_wrap returnt sowohl den core-Text als
    # auch den Anker (falls vorhanden).
    core, existing_anchor = strip_existing_wrap(core)
    # #475 (Hans, 2026-06-02): einen nachgestellten nackten Block-Anker
    # (`… ^abc123`) aus dem Wrap-Text ziehen — sonst landet er SICHTBAR im
    # Highlight (Hans-Report: „man sieht den Anker") und blockiert das
    # Ent-/Umwrappen. Wird, falls kein Highlight-Anker existiert, als der
    # Highlight-Anker wiederverwendet (Link bleibt stabil).
    core, trailing_anchor = strip_trailing_block_anchor(core)
    # #449: fuehrenden Block-Marker abtrennen und ausserhalb des Wraps
    # lassen — sonst bricht das Listen-/Blockquote-/Heading-Rendering.
    # Nach strip_existing_wrap angewandt, damit ein bereits (evtl. noch
    # fehlerhaft) gewrapptes Listen-Item beim Re-Color selbst-heilt.
    prefix = core[BLOCK_PREFIX_RE, 1].to_s
    rest   = core[prefix.length..].to_s
    if @color == UNWRAP_TOKEN
      # Unwrap: Block-Anker (falls vorhanden) als nackten Trailing-Anker
      # wieder anhaengen, damit der Absatz verlinkbar/ankerbar bleibt.
      keep = existing_anchor || trailing_anchor
      new_block = keep ? "#{core} ^#{keep}" : core
    else
      # #617 v2: Renderer-Regex deckelt bei 4000 Zeichen — laengere Wraps
      # wuerden als ==rot|…-Klartext erscheinen. Lieber sauber ablehnen.
      if rest.length > 4000
        raise Error, "Absatz zu lang für ein Highlight (#{rest.length} Zeichen, max. 4000)"
      end
      anchor    = existing_anchor || trailing_anchor || generate_anchor
      @result_anchor = anchor
      new_block = "#{prefix}==#{@color}|#{rest}==^#{anchor}"
    end
    [lines[0...first].join, new_block, trailing_ws, lines[(last + 1)..]&.join.to_s].join
  end

  def wrap_substring(body, block_lines)
    lines = body.lines
    first = block_lines.first
    last  = block_lines.last
    block_text = lines[first..last].join
    needle = @selected_text
    if @color == UNWRAP_TOKEN
      # Unwrap-Mode: bestehende `==color|needle==(^id)?`-Wraps um
      # diesen needle abstreifen (mit oder ohne Anker).
      stripped = block_text.gsub(/==(#{COLORS.join('|')})\|#{Regexp.escape(needle)}==(?:\^#{ANCHOR_PAT})?/, needle)
      raise Error, "Selektion nicht eingewrapped" if stripped == block_text
      return [lines[0...first].join, stripped, lines[(last + 1)..]&.join.to_s].join
    end
    # #387 Phase A-Fix2 (Hans, 2026-05-28): selectedText kommt aus
    # `sel.toString()` und enthaelt KEINE Wrap-Marker (Browser
    # rendert `<mark>foo</mark>` zu Text „foo"). Im Source-Body
    # steht aber `==color|foo==`. Wenn der needle sich in einer
    # bereits gewrappten Stelle befindet (z.B. User hat Teil eines
    # bestehenden Highlights neu selektiert), entstehen sonst
    # nested-wraps und die HIGHLIGHT_RE matcht spaeter ein einzelnes
    # Zeichen am falschen Ort.
    #
    # Strategie:
    #  1. Alle bestehenden Wraps im Block lokalisieren (Position +
    #     Core-Text + Anker).
    #  2. Schauen, ob unser needle im Core-Text einer dieser Wraps
    #     liegt (Substring eines existierenden Wraps).
    #  3. Falls ja: den ganzen Wrap abstreifen (Anker und Core
    #     beibehalten fuer evtl. Re-Use), dann den needle frisch
    #     wrappen — das Anker-ID des aelteren Wraps uebernehmen.
    existing_anchor = nil
    cleaned         = block_text.dup
    wraps           = []
    scan_re         = /==(?:#{COLORS.join('|')})\|([^=]{1,4000}?)==(?:\^(#{ANCHOR_PAT}))?/m
    block_text.scan(scan_re) do
      md = Regexp.last_match
      wraps << { wrap_start: md.begin(0), wrap_end: md.end(0),
                 core: md[1], anchor: md[2] }
    end

    # #617 (Hans): verallgemeinert — die Selektion kann einen bestehenden
    # Wrap exakt treffen (Re-Color), in ihm liegen (Ausschnitt) ODER seine
    # GRENZE ueberlappen (beginnt davor/endet dahinter — z.B. Highlight
    # endet am Blockende und die Auswahl reicht darueber hinaus). Frueher
    # deckten zwei Spezialfaelle nur exakt/enthalten ab; bei Grenz-
    # Ueberlappung fand die Suche den needle nicht ("Selektion im Block
    # nicht gefunden"). Jetzt: Plain-Sicht des Blocks bauen (alle Wraps
    # -> Core), needle dort lokalisieren, alle GESCHNITTENEN Wraps im
    # Source abstreifen (Anker des ersten wird wiederverwendet) und dann
    # frisch wrappen.
    plain = +""
    pos_src = 0
    wraps.each do |w|
      plain << block_text[pos_src...w[:wrap_start]]
      w[:plain_start] = plain.length
      plain << w[:core]
      w[:plain_end] = plain.length
      pos_src = w[:wrap_end]
    end
    plain << block_text[pos_src..].to_s

    if (p_idx = plain.index(needle))
      n_end = p_idx + needle.length
      hit = wraps.select { |w| w[:plain_start] < n_end && p_idx < w[:plain_end] }
      if hit.any?
        existing_anchor = hit.map { |w| w[:anchor] }.compact.first
        hit.sort_by { |w| -w[:wrap_start] }.each do |w|
          cleaned[w[:wrap_start]...w[:wrap_end]] = w[:core]
        end
      end
    end

    # #492 (Hans, 2026-06-03): Exakte Substring-Suche scheitert, wenn die
    # Selektion Inline-Markup ueberspannt (z.B. **fett**, `code`) — die DOM-
    # Auswahl (sel.toString()) enthaelt die Marker NICHT, die Source schon.
    # Fallback: markup-tolerant die passende Quell-Span finden und DIESE
    # wrappen (die Marker bleiben innerhalb des Highlights erhalten).
    idx_clean = cleaned.index(needle)
    if idx_clean
      span_len = needle.length
    else
      span = markup_tolerant_span(cleaned, needle)
      raise Error, "Selektion im Block nicht gefunden" unless span
      idx_clean, span_len = span
    end
    if span_len > 4000
      raise Error, "Auswahl zu lang für ein Highlight (#{span_len} Zeichen, max. 4000)"
    end
    anchor    = existing_anchor || generate_anchor
    @result_anchor = anchor
    src_span  = cleaned[idx_clean, span_len]
    wrapped   = "==#{@color}|#{src_span}==^#{anchor}"
    new_block = cleaned.dup
    new_block[idx_clean, span_len] = wrapped
    [lines[0...first].join, new_block, lines[(last + 1)..]&.join.to_s].join
  end

  # #751 (Hans, 2026-06-21): Regex aus dem needle, bei dem jeder
  # Whitespace-Run (Spaces, Newlines, Quell-Einrückung) flexibel `\s+`
  # matcht und der übrige Text literal bleibt. So findet eine über
  # eingerückte Zeilen gezogene DOM-Selektion ihre Quell-Span wieder.
  def whitespace_flexible_re(needle)
    src = needle.split(/(\s+)/).map do |p|
      p.match?(/\A\s+\z/) ? '\s+' : Regexp.escape(p)
    end.join
    Regexp.new(src)
  end

  WORD_CHAR = /[\p{L}\p{N}]/

  # #492 (Hans, 2026-06-03): Findet die Quell-Span [start, len], deren
  # markup-bereinigte Form `needle` entspricht — tolerant gegen Inline-
  # Markup, das die DOM-Selektion nicht enthaelt (Fett, Kursiv, `Code`).
  # WICHTIG: Code-Inhalt + intraword-`_` (z.B. `anchor_id`) bleiben WORT-
  # GETREU erhalten — nur echte Formatierungs-Marker werden ignoriert.
  # Die Span wird so erweitert, dass alle enthaltenen Marker ihren Partner
  # mit drin haben (sonst entstuende ungueltiges Markdown). nil, wenn nicht
  # gefunden oder nicht balancierbar.
  def markup_tolerant_span(text, needle)
    return nil if needle.empty?
    markers = scan_markers(text)
    ranges  = markers.map { |m| (m[:start]...(m[:start] + m[:len])) }

    plain = +""
    map   = []
    i = 0
    while i < text.length
      if (r = ranges.find { |rng| rng.cover?(i) })
        i = r.end                       # ganzen Marker ueberspringen
      else
        map << i
        plain << text[i]
        i += 1
      end
    end

    # #751 (Hans, 2026-06-21): whitespace-tolerant suchen. Die DOM-Selektion
    # (sel.toString()) kollabiert Quell-Einrückung und harte Zeilenumbrüche —
    # ein über mehrere eingerückte Fortsetzungszeilen (Listenpunkt/Absatz)
    # gezogener Satz kommt als "…is\ninterchangeable…", die Source hat aber
    # "…is\n   interchangeable…". Exaktes plain.index scheitert daran
    # ("Selektion im Block nicht gefunden"). Jeder Whitespace-Run im needle
    # matcht daher einen beliebigen Whitespace-Run in plain.
    m = plain.match(whitespace_flexible_re(needle))
    return nil unless m
    pos         = m.begin(0)
    matched_len = m.end(0) - m.begin(0)
    return nil if matched_len.zero?
    s = map[pos]
    f = map[pos + matched_len - 1] + 1   # exklusiv

    partners = pair_markers(markers)
    50.times do
      inside = markers.select { |m| m[:start] >= s && (m[:start] + m[:len]) <= f }
      bad = inside.find do |m|
        p = partners[m.object_id]
        p.nil? || !(p[:start] >= s && (p[:start] + p[:len]) <= f)
      end
      break unless bad
      p = partners[bad.object_id]
      return nil unless p                # unpaariger Marker -> aufgeben
      s = [s, p[:start]].min
      f = [f, p[:start] + p[:len]].max
    end
    [s, f - s]
  end

  # Scannt die echten Inline-Formatierungs-Marker (kein Inhalt). Beachtet:
  #  - Code-Spans (`…`): innerhalb gelten KEINE weiteren Marker.
  #  - `_` ist nur Marker an Wortgrenzen (intraword-`_` = literal, CommonMark).
  def scan_markers(text)
    markers = []
    i = 0
    in_code = false
    while i < text.length
      if text[i] == "`"
        markers << { start: i, len: 1, type: :code }
        in_code = !in_code
        i += 1
        next
      end
      if in_code
        i += 1
        next
      end
      if text[i, 2] == "**"
        markers << { start: i, len: 2, type: :strong_star }; i += 2; next
      end
      if text[i, 2] == "__"
        markers << { start: i, len: 2, type: :strong_us }; i += 2; next
      end
      if text[i] == "*"
        markers << { start: i, len: 1, type: :em_star }; i += 1; next
      end
      if text[i] == "_" && emphasis_underscore?(text, i)
        markers << { start: i, len: 1, type: :em_us }; i += 1; next
      end
      i += 1
    end
    markers
  end

  # `_` ist Emphasis nur an einer Wortgrenze — wenn BEIDE Nachbarn Wort-
  # zeichen sind (z.B. anchor_id), ist es literal.
  def emphasis_underscore?(text, i)
    before = i > 0 ? text[i - 1] : " "
    after  = i < text.length - 1 ? text[i + 1] : " "
    !(before =~ WORD_CHAR && after =~ WORD_CHAR)
  end

  # Paart Marker je Typ in Reihenfolge (1.<->2., 3.<->4., …). Liefert
  # object_id -> Partner-Marker.
  def pair_markers(markers)
    partners = {}
    markers.group_by { |m| m[:type] }.each_value do |list|
      list.each_slice(2) do |a, b|
        next unless b
        partners[a.object_id] = b
        partners[b.object_id] = a
      end
    end
    partners
  end

  # Falls der Block schon einen `==color|...==(^id)?`-Wrap drin hat,
  # das Wrap-Markup entfernen — gib den Text + (falls vorhanden) den
  # alten Anker zurueck, damit der Re-Wrap die ID stabil halten kann.
  def strip_existing_wrap(text)
    anchor = nil
    stripped = text.gsub(/==(#{COLORS.join('|')})\|(.+?)==(?:\^(#{ANCHOR_PAT}))?/m) do
      anchor ||= Regexp.last_match(3)
      Regexp.last_match(2)
    end
    [stripped, anchor]
  end

  # #475 (Hans, 2026-06-02): nachgestellten nackten Block-Anker (`… ^id`)
  # vom Block-Ende abtrennen. Liefert [text_ohne_anker, anker_oder_nil].
  def strip_trailing_block_anchor(text)
    if (m = text.match(TRAILING_ANCHOR_RE))
      [text[0...m.begin(0)], m[1]]
    else
      [text, nil]
    end
  end

  # 8-Hex-Anker fuer eine Highlight-ID. SecureRandom.hex(4) ergibt 8
  # Hex-Zeichen — bei ~16.7M Kombinationen praktisch kollisionsfrei
  # innerhalb eines KIs. Globale Eindeutigkeit gegen die DB pruefen
  # ist Overkill — Markdown-Files sind die Quelle der Wahrheit, beim
  # Schreibzugriff koennen wir das ggf. nachziehen.
  def generate_anchor
    require "securerandom" unless defined?(SecureRandom)
    SecureRandom.hex(4)
  end

  # #480 Increment 2 (Hans, 2026-06-03): die Markdown-Flaeche kann auch
  # eine Task-Description sein (kein KI/File, sondern die DB-Spalte). Die
  # Wrap-Logik selbst ist quell-agnostisch (block_line_indices ist rein);
  # nur Read/Write unterscheiden KI (FileProxy) vs. Task (description).
  def read_body
    if @item.is_a?(Task)
      @item.description.to_s
    else
      FileProxy.read_body(actor: @actor, knowledge_item: @item)
    end
  end

  def write_body(new_body)
    if @item.is_a?(Task)
      @item.update!(description: new_body)
    else
      FileProxy::Writer.update(actor: @actor, knowledge_item: @item, content: new_body)
    end
  end
end
