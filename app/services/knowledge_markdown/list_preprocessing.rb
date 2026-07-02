# #564: Markdown-Preprocessing für Listen/HR/juristische Gliederung — aus
# knowledge_markdown.rb extrahiert (reiner Code-Move, #500/#561).
class KnowledgeMarkdown
  module ListPreprocessing
    extend ActiveSupport::Concern

    # Redcarpet (CommonMark-Strict) erkennt eine Liste nur, wenn ihr eine
    # Leerzeile vorausgeht — die fügen wir pre-render ein.
    LIST_ITEM_RE = /\A(\s*)(?:[*\-+]|\d+\.)\s/.freeze

    # #561: Style-Token für juristische Gliederungs-Listen (LP = (n)-Klammer-
    # Dezimal, LA = Buchstabe-Klammer); werden im Postprocess zu CSS-Klassen.
    LEGAL_TOKEN_LP = "⟦LP⟧"
    LEGAL_TOKEN_LA = "⟦LA⟧"

    private

    # #500: nur das Leading-Frontmatter (`---`…`---` am Dateianfang)
    # entfernen — NICHT eine evtl. erste H1 (anders als strip_frontmatter_and_h1).
    def strip_leading_frontmatter(raw)
      s = raw.to_s
      return s unless s.start_with?("---")
      parts = s.split(/^---[ \t]*$/, 3)
      parts.size >= 3 ? parts[2].to_s.sub(/\A\n+/, "") : s
    end

    # #500: Eine Zeile aus nur `---` (3+ Bindestriche) soll IMMER als <hr>
    # rendern. Ohne Leerzeile davor liest Redcarpet sie als Setext-
    # Unterstreichung. Fix: Leerzeile einfügen; Frontmatter + Code-Fences
    # bleiben unangetastet.
    def ensure_blank_line_before_hr(md)
      lines = md.lines
      out   = []
      in_code = false
      in_frontmatter = false
      lines.each_with_index do |line, i|
        stripped = line.strip
        if i.zero? && stripped == "---"
          in_frontmatter = true
          out << line
          next
        end
        if in_frontmatter
          out << line
          in_frontmatter = false if stripped == "---"
          next
        end
        if stripped.start_with?("```") || stripped.start_with?("~~~")
          in_code = !in_code
          out << line
          next
        end
        if !in_code && stripped =~ /\A-{3,}\z/
          prev = i.positive? ? lines[i - 1].strip : ""
          out << "\n" if !prev.empty? && !out.empty?
        end
        out << line
      end
      out.join
    end

    # #561: juristische Gliederungs-Aufzählungen — Zeilen mit (1)/(2)… oder
    # a)/b)… als echte Listen rendern (Redcarpet kennt diese Marker nicht).
    # a)-Unterpunkte unter (n) mit nur 3 Spaces einrücken (4 = Code-Block!);
    # a) auch top-level (§ 3); Bullets unter (n) ebenfalls 3 Spaces. Leerzeilen
    # INNERHALB einer Aufzählung werden übersprungen (tight list), sonst
    # Originalzeilen unverändert. Code-Fences bleiben unangetastet.
    def convert_legal_enumerations(md)
      out = []
      in_dec = false        # innerhalb einer (n)-Liste
      in_alpha_top = false  # innerhalb einer top-level a)-Liste (#561: § 3)
      in_fence = false      # innerhalb ```/~~~ Code-Fence
      dec_n = 0
      alpha_n = 0
      md.each_line do |raw|
        line = raw.chomp
        was_enum = in_dec || in_alpha_top
        if line.match?(/\A\s*(```|~~~)/)
          in_fence = !in_fence
          in_dec = in_alpha_top = false; dec_n = alpha_n = 0
          out << "" if was_enum && out.last && !out.last.empty?
          out << line
        elsif in_fence
          out << line
        elsif (m = line.match(/\A\((\d{1,3})\)\s+(.+)\z/))
          in_dec = true; in_alpha_top = false; dec_n += 1; alpha_n = 0
          out << "#{dec_n}. #{LEGAL_TOKEN_LP}#{m[2]}"
        elsif (m = line.match(/\A([a-z]{1,2})\)\s+(.+)\z/i))
          if in_dec
            alpha_n += 1
            out << "   #{alpha_n}. #{LEGAL_TOKEN_LA}#{m[2]}"   # 3 Spaces → unter (n)
          else
            in_alpha_top = true; alpha_n += 1
            out << "#{alpha_n}. #{LEGAL_TOKEN_LA}#{m[2]}"      # top-level a)-Liste
          end
        elsif in_dec && line.match?(/\A\s*[-*+]\s+/)
          alpha_n = 0
          out << "   #{line.lstrip}"                            # Bullet 3 Spaces
        elsif line.strip.empty?
          out << line unless was_enum
        elsif line.match?(/\A\s*(\#|---|\*\*\*|___)/)
          in_dec = in_alpha_top = false; dec_n = alpha_n = 0     # Heading/HR
          out << "" if was_enum && out.last && !out.last.empty?  # Liste trennen
          out << line
        else
          in_dec = in_alpha_top = false; dec_n = alpha_n = 0
          out << "" if was_enum && out.last && !out.last.empty?  # Liste trennen
          out << line
        end
      end
      out.join("\n")
    end

    def apply_legal_list_classes(html)
      html = html.gsub(/<ol>(\s*<li>(?:<p>)?)#{Regexp.escape(LEGAL_TOKEN_LP)}/, '<ol class="legal-paren-decimal">\1')
      html = html.gsub(/<ol>(\s*<li>(?:<p>)?)#{Regexp.escape(LEGAL_TOKEN_LA)}/, '<ol class="legal-paren-alpha">\1')
      html.gsub(/#{Regexp.escape(LEGAL_TOKEN_LP)}|#{Regexp.escape(LEGAL_TOKEN_LA)}/, "")
    end

    def ensure_blank_line_before_lists(md)
      lines = md.lines
      out   = []
      prev_was_list = false
      lines.each_with_index do |line, i|
        is_list  = line =~ LIST_ITEM_RE
        prev_line = i > 0 ? lines[i - 1] : ""
        prev_blank = prev_line.strip.empty?
        if is_list && !prev_was_list && !prev_blank && !out.empty?
          out << "\n"
        end
        out << line
        prev_was_list = !!is_list
      end
      out.join
    end

    # Redcarpet erwartet pro Verschachtelungs-Ebene 4 Spaces für Bullet-
    # Listen, viele Editoren rücken aber 2 ein. Wir erkennen die Einheit
    # pro Datei und blasen sie auf 4 auf. Ordered Lists bleiben unangetastet.
    def normalize_list_indent(md)
      indents = md.scan(/^( +)[*+\-] /).map { |m| m[0].length }.uniq
      return md if indents.empty?
      unit = indents.min
      return md if unit >= 4

      md.gsub(/^( +)([*+\-] )/) do
        spaces = Regexp.last_match(1)
        marker = Regexp.last_match(2)
        levels = spaces.length / unit
        (" " * (levels * 4)) + marker
      end
    end
  end
end
