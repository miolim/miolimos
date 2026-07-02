# #564: Embed-Expansion (`![[Page]]`, `![[Page#Heading]]`, `![[Page^block]]`)
# — aus knowledge_markdown.rb extrahiert (reiner Code-Move, #132).
class KnowledgeMarkdown
  module Embeds
    extend ActiveSupport::Concern

    EMBED_RE        = /!\[\[([^\]|#\^]+)(?:#([^\]|]+))?(?:\^([^\]|]+))?\]\]/
    MAX_EMBED_DEPTH = 2
    IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .svg .avif].freeze

    class_methods do
      def strip_frontmatter_and_h1(raw)
        body = raw
        if body.start_with?("---")
          parts = body.split(/^---\s*$/, 3)
          body  = parts[2].to_s.sub(/\A\n/, "") if parts.size >= 3
        end
        body.sub(/\A# [^\n]*\n+/, "")
      end
    end

    private

    # `![[Page]]`, `![[Page#Heading]]`, `![[Page^block-id]]` werden vor
    # dem Markdown-Render durch den eingebetteten Inhalt der Ziel-Notiz
    # ersetzt. Tiefen-Limit (MAX_EMBED_DEPTH) plus Loop-Schutz über
    # @embed_stack verhindern Endlos-Embed-Kreise.
    def expand_embeds(md)
      md.gsub(EMBED_RE) do
        target_id  = Regexp.last_match(1).strip
        heading    = Regexp.last_match(2)&.strip
        block_anch = Regexp.last_match(3)&.strip
        target     = Wikilinks.lookup_target(target_id)

        next "*[Embed: #{target_id} — nicht gefunden]*" unless target

        # #132: Bild-KI als <img> einbinden statt Body-Inline.
        if image_target?(target)
          next render_image_embed(target, heading)
        end

        if @embed_depth >= MAX_EMBED_DEPTH || @embed_stack.include?(target.uuid)
          next %(<blockquote class="text-xs text-slate-500 italic">Embed-Limit erreicht: <a href="/knowledge_items/#{target.uuid}" class="wikilink">#{target.title}</a></blockquote>)
        end

        raw = read_target_body(target)
        next "*[Embed: #{target.title} — leer]*" if raw.blank?

        slice = if block_anch
                  extract_block(raw, block_anch)
                elsif heading
                  extract_section(raw, heading)
                else
                  raw
                end

        next "*[Embed: #{target.title} — Anker `#{block_anch || heading}` nicht gefunden]*" if slice.nil? || slice.strip.empty?

        embedded_html = self.class.new(slice, item: target,
                                              embed_depth: @embed_depth + 1,
                                              embed_stack: @embed_stack + [target.uuid]).render
        header = %(<div class="text-xs text-slate-500 mb-1 not-prose">↳ <a href="/knowledge_items/#{target.uuid}" class="wikilink text-emerald-700 hover:underline">#{CGI.escapeHTML(target.title)}</a>#{heading ? " · #{CGI.escapeHTML(heading)}" : ''}#{block_anch ? " ^#{block_anch}" : ''}</div>)
        %(\n\n<aside class="embed border-l-2 border-emerald-300 pl-3 my-3 bg-emerald-50/40 rounded-r py-2">#{header}#{embedded_html}</aside>\n\n)
      end
    end

    def image_target?(target)
      ext = File.extname(target.file_path.to_s).downcase
      IMAGE_EXTENSIONS.include?(ext)
    end

    # Bild-KI als <img src=...>-Tag inline einbinden. `heading` wird als
    # Caption-Text genutzt (Obsidian-Konvention).
    def render_image_embed(target, caption_text)
      src     = "/knowledge_items/#{target.uuid}/file"
      alt     = CGI.escapeHTML(caption_text.presence || target.title)
      caption = caption_text.present? ? %(<figcaption class="text-xs text-slate-500 mt-1">#{CGI.escapeHTML(caption_text)}</figcaption>) : ""
      %(<figure class="my-3"><img src="#{src}" alt="#{alt}" class="max-w-full h-auto rounded">#{caption}</figure>)
    end

    # Body lesen für Embed — strippt Frontmatter + H1, damit der
    # eingebettete Content sauber rein-rendert.
    def read_target_body(target)
      raw = FileProxy.read(actor: Current.actor, knowledge_item: target)
      self.class.send(:strip_frontmatter_and_h1, raw)
    rescue
      nil
    end

    # Findet den Block, dessen letzte Zeile mit `^anchor` markiert ist.
    # Liefert den Block als Markdown-String oder nil.
    def extract_block(body, anchor)
      body.lines.each_with_index do |line, idx|
        next unless line.rstrip =~ /\s\^#{Regexp.escape(anchor)}\s*\z/
        # Block-Anfang: vorhergehende nicht-leere Zeilen sammeln
        start = idx
        start -= 1 while start > 0 && !body.lines[start - 1].strip.empty? && body.lines[start - 1] !~ /\A\s*[*\-+]\s|\A\s*\d+\.\s/
        block_lines = body.lines[start..idx].map(&:rstrip).map { |l| l.sub(/\s\^#{Regexp.escape(anchor)}\s*\z/, "") }
        return block_lines.join("\n")
      end
      nil
    end

    # Findet eine Heading-Section (## Heading … bis zum nächsten Heading
    # gleicher oder höherer Ebene). Liefert den Inhalt als Markdown.
    def extract_section(body, heading)
      target_text = heading.downcase.strip
      lines = body.lines
      start_idx = lines.index do |l|
        m = l.match(/\A#+\s+(.+?)\s*\z/)
        m && m[1].downcase.strip == target_text
      end
      return nil unless start_idx

      start_level = lines[start_idx].match(/\A(#+)/)[1].length
      end_idx     = lines[(start_idx + 1)..].index do |l|
        m = l.match(/\A(#+)\s/)
        m && m[1].length <= start_level
      end
      end_idx = end_idx ? start_idx + 1 + end_idx - 1 : lines.size - 1
      lines[(start_idx + 1)..end_idx].join.strip
    end
  end
end
