require "securerandom"

# Verwaltet Block-Anker im Markdown-Source (`^abc`-Suffix am Zeilenende).
# Stellt sicher, dass clientseitige `block-N`-Indexierung (DOM-Position
# unter den anker-LOSEN Blocks) und serverseitige Block-Adressierung
# konsistent bleiben.
class KnowledgeBlockAnchor
  ANCHOR_SUFFIX = /\s+\^[a-z0-9][a-z0-9-]*\s*\z/.freeze
  LIST_MARKER   = /\A\s*(?:[*\-+]|\d+\.)\s/.freeze

  def initialize(item, actor:)
    @item  = item
    @actor = actor
  end

  # Setzt einen stabilen Anker an den n-ten ANKER-LOSEN Block (1-basiert).
  # Liefert die Anker-ID. Liefert nil, wenn n außerhalb des Bereichs liegt.
  # Side effect: schreibt das Source-Markdown via FileProxy.update.
  def ensure!(n)
    body = read_body
    blocks = block_line_indices(body)
    unanchored = blocks.reject { |idxs| body.lines[idxs.last].rstrip =~ ANCHOR_SUFFIX }
    return nil if n < 1 || n > unanchored.size

    last_line_idx = unanchored[n - 1].last
    lines = body.lines
    target_line = lines[last_line_idx].rstrip

    # #466 (Hans, 2026-06-02): Anker-Format vereinheitlicht — Block-Anker
    # werden jetzt wie Highlight-Anker als 8-stelliger Hex erzeugt
    # (SecureRandom.hex(4)). Ein gemeinsames Format = ein mentales Modell,
    # eine Regex. Bestehende 6-stellige Anker bleiben gueltig (Parser/
    # Validierung akzeptieren beide) — kein Daten-Backfill noetig.
    new_id = SecureRandom.hex(4)
    lines[last_line_idx] = "#{target_line} ^#{new_id}\n"
    write_body(lines.join)
    new_id
  end

  # Liefert den Plain-Text des Blocks mit dem gegebenen Anker. Für die
  # Comment-Title-Snippet-Erzeugung. Strippt Markdown-Marker grob.
  def text_at(anchor)
    body = read_body
    block_line_indices(body).each do |idxs|
      lines = idxs.map { |i| body.lines[i] }.join
      next unless lines.include?("^#{anchor}")
      return lines.gsub(/\^#{Regexp.escape(anchor)}/, "")
                  .gsub(/^[*\-+]\s+|^\d+\.\s+|^>\s+|^\s*#+\s+/, "")
                  .gsub(/\[\[([^\]|^#]+)[^\]]*\]\]/, '\1')
                  .gsub(/[*_`]/, "")
                  .strip
    end
    ""
  end

  private

  # #480 Inc.3 (Hans, 2026-06-03): task-aware — eine Task speichert ihren
  # Markdown in der `description`-Spalte (kein FileProxy), wie schon im
  # BodyHighlightWrapper. So funktioniert ensure!/text_at auch fuer
  # Task-Absaetze.
  def read_body
    if @item.is_a?(Task)
      @item.description.to_s
    else
      FileProxy.read_body(actor: @actor, knowledge_item: @item)
    end
  end

  def write_body(content)
    if @item.is_a?(Task)
      @item.update!(description: content)
    else
      FileProxy.update(actor: @actor, knowledge_item: @item, content: content)
    end
  end

  # Block-Indizes nach Quell-Zeilen. Listen-Items werden als eigene
  # Blocks gewertet (jede Bullet/numbered-Zeile beginnt einen neuen
  # Block), damit block-N im Server mit der DOM-Reihenfolge im Client
  # matcht (jedes `<li>` zählt separat).
  #
  # Nicht zählen: Headings (#…), Horizontal Rules, Code-Block-Inhalte.
  # Diese Elemente werden im Client von der p/li/blockquote-Iteration
  # (siehe knowledge_markdown.rb#inject_block_ids und paragraph_actions
  # _controller#augment) ebenfalls übersprungen — sonst verschiebt sich
  # die Anker-Nummerierung gegen den DOM.
  def block_line_indices(body)
    blocks  = []
    current = nil
    in_code_block = false
    in_frontmatter = false
    body.lines.each_with_index do |line, i|
      stripped = line.strip

      # #500 (Hans, 2026-06-04): Leading-Frontmatter (`---`…`---` ganz oben)
      # zaehlt NICHT als Block — sonst verschiebt es die Block-Nummerierung
      # gegenueber dem Render (der das Frontmatter ueberspringt). Die
      # Original-Zeilenindizes der Inhalts-Bloecke bleiben erhalten, also
      # schreibt ensure! weiterhin an die richtige Stelle im vollen Body.
      if i.zero? && stripped == "---"
        in_frontmatter = true
        next
      end
      if in_frontmatter
        in_frontmatter = false if stripped == "---"
        next
      end

      # Code-Fence: alle Zeilen innerhalb komplett ignorieren, inklusive
      # der Fence-Zeilen selbst.
      if stripped.start_with?("```") || stripped.start_with?("~~~")
        blocks << current if current
        current = nil
        in_code_block = !in_code_block
        next
      end
      next if in_code_block

      # Horizontal Rules zaehlen nicht. Headings ZAEHLEN — Hans (#341,
       # 2026-05-24): Headings sind anker-faehig wie Absaetze, sodass
       # Wikilinks auch zu bestimmten Heading-Positionen verweisen
       # koennen.
      if stripped =~ /\A(?:-{3,}|\*{3,}|_{3,})\s*\z/
        blocks << current if current
        current = nil
        next
      end
      if stripped =~ /\A\#+\s/
        blocks << current if current
        # Heading ist immer ein Single-Line-Block.
        blocks << [i]
        current = nil
        next
      end

      # #413 (Hans, 2026-05-30): einzelner `>`-Marker (lone blockquote
      # continuation) trennt einen Blockquote in mehrere Absaetze.
      # In der MD-Quelle bedeutet `> para1\n>\n> para2` zwei
      # Paragraphen — soll auch hier so gezaehlt werden, damit jeder
      # Absatz einzeln selektierbar/ankerbar ist.
      if stripped.empty? || stripped == ">"
        blocks << current if current
        current = nil
      elsif line =~ LIST_MARKER
        blocks << current if current
        current = [i]
      else
        current ||= []
        current << i
      end
    end
    blocks << current if current
    blocks
  end
end
