# #564: Block-IDs + Backlink-Indikatoren — aus knowledge_markdown.rb
# extrahiert (reiner Code-Move, #341/#387/#413/#465/#466/#475/#498).
class KnowledgeMarkdown
  module Blocks
    extend ActiveSupport::Concern

    # #341: Headings (h1..h6) zaehlen MIT als ankerbare Bloecke. Die DOM-
    # Indexierung muss mit KnowledgeBlockAnchor#block_line_indices
    # uebereinstimmen — beide zaehlen Headings inkl.
    BLOCK_TAGS = %w[p li blockquote h1 h2 h3 h4 h5 h6].freeze

    BACKLINK_ICON =
      %(<svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-3 h-3 align-middle" ) +
      %(viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">) +
      %(<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>) +
      %(<path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>).freeze

    class_methods do
      # #465/#466: block-N-IDs auf Leaf-Bloecke setzen, damit paragraph-actions
      # auch in Antworten greift. Schlanke Variante von inject_block_ids ohne
      # Backlink-Indikatoren — fuer den Inline-Renderer.
      def assign_block_ids(html)
        doc = Nokogiri::HTML::DocumentFragment.parse(html.to_s)
        block_index = 0
        doc.css(BLOCK_TAGS.join(", ")).each do |node|
          next if node["id"]
          next if node.css(BLOCK_TAGS.join(", ")).any?  # nur Leaf-Bloecke
          block_index += 1
          # #466: nachgestellten `^id`-Anker als stabile Block-id heben, statt
          # ihn als rohen Text zu zeigen. block_index zaehlt trotzdem jede
          # Leaf-Position, damit block-N zur Anker-Aufloesung passt.
          inner = node.inner_html
          if (m = inner.match(/[ \t]*\^([a-z0-9][a-z0-9-]*)\s*\z/))
            node.inner_html = inner[0...m.begin(0)]
            node["id"] = m[1]
          else
            node["id"] = "block-#{block_index}"
          end
        end
        doc.to_html
      end

      # #475: als Klassen-Methode verfuegbar, damit der Inline-Renderer
      # (Antworten/Kommentare) denselben Indikator injizieren kann.
      def backlink_indicator_html(anchor, sources)
        count = sources.size
        %(&nbsp;<a href="#" class="backlink-indicator inline-block align-middle px-1 rounded text-xs ) +
          %(text-emerald-700 hover:bg-emerald-50 no-underline" ) +
          %(data-action="click->paragraph-actions#showBacklinks" ) +
          %(data-anchor="#{anchor}" ) +
          %(data-source-uuids="#{sources.join(',')}" ) +
          %(title="#{count} Backlink#{'s' if count > 1}">#{BACKLINK_ICON}&nbsp;#{count}</a>)
      end

      # #475: Backlink-Indikatoren in bereits gerendertes (und sanitiztes)
      # HTML einer Antwort injizieren — NACH dem Sanitize, weil der Indikator
      # <svg> + data-Attribute enthaelt, die der Inline-Sanitizer entfernt.
      def inject_backlink_indicators_for(html, item)
        return html if item.nil?
        data = KnowledgeItemReference.where(target_uuid: item.uuid, anchor_type: :block)
                                     .where(source_uuid: KnowledgeItem.select(:uuid))
                                     .pluck(:anchor_text, :source_uuid)
                                     .group_by(&:first)
                                     .transform_values { |rows| rows.map(&:last).uniq }
        return html if data.empty?
        doc = Nokogiri::HTML::DocumentFragment.parse(html.to_s)
        doc.css(BLOCK_TAGS.join(", ")).each do |node|
          id = node["id"]
          next if id.nil? || id.empty?
          sources = data[id]
          next if sources.nil? || sources.empty?
          next if node.at_css(".backlink-indicator")
          node.add_child(Nokogiri::HTML::DocumentFragment.parse(backlink_indicator_html(id, sources)))
        end
        doc.to_html
      end
    end

    private

    # Pass 1: Marker-Spans (data-anchor) auf den nächsten Block-Container
    #         übertragen, Counter anhängen, Marker entfernen.
    # Pass 2: Verbleibende Blocks bekommen positionsbasierte block-N-IDs.
    def inject_block_ids(html, backlink_data)
      doc = Nokogiri::HTML::DocumentFragment.parse(html)

      doc.css("span[data-anchor]").each do |span|
        block = span.ancestors.find { |a| a.element? && BLOCK_TAGS.include?(a.name) }
        span.remove
        next unless block
        next if block["id"]

        anchor = span["data-anchor"]
        block["id"] = anchor

        sources = backlink_data[anchor] || []
        next if sources.empty?
        block.add_child(Nokogiri::HTML::DocumentFragment.parse(backlink_indicator_html(anchor, sources)))
      end

      # #413: pro Markdown-Source-Paragraph genau ein block-N. Nur Leaf-
      # Bloecke bekommen block-N; #498: NUR echte Mehr-Absatz-Wrapper
      # (direkte <p>-Kinder) ueberspringen — nicht Listen-Eltern mit
      # verschachtelter <ul>/<ol>.
      block_index = 0
      doc.css(BLOCK_TAGS.join(", ")).each do |node|
        next if node["id"]
        next if node.element_children.any? { |c| c.name == "p" }
        block_index += 1
        node["id"] = "block-#{block_index}"
      end

      doc.to_html
    end

    def backlink_data_for(item)
      KnowledgeItemReference.where(target_uuid: item.uuid, anchor_type: :block)
                            .where(source_uuid: KnowledgeItem.select(:uuid))
                            .pluck(:anchor_text, :source_uuid)
                            .group_by(&:first)
                            .transform_values { |rows| rows.map(&:last) }
    end

    def backlink_indicator_html(anchor, sources)
      self.class.backlink_indicator_html(anchor, sources)
    end
  end
end
