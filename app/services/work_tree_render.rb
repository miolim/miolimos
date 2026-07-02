# #325 Phase 3a (Hans, 2026-05-24): Work-Tree-Render. Walked die
# Topic-Tree-Struktur, emittiert HTML mit Heading-Level = Tree-Tiefe,
# Body der jeweiligen KI dazwischen. Render-Pfad fuer die Vorschau
# (spaeter auch fuer Publish).
#
# Referenz-Wikilinks (`((Title))`-Syntax oder `[[Title|cite]]`-Variante)
# kommen in Phase 3b — diese Implementation rendert nur die Struktur.
class WorkTreeRender
  HEADING_CAP = 6  # ueber HTML's H6 hinaus gibt es nichts

  def self.call(topic, root_level: 1, number_headings: true)
    new(topic, root_level: root_level, number_headings: number_headings).render
  end

  def initialize(topic, root_level:, number_headings:)
    @topic           = topic
    @root_level      = root_level
    @number_headings = number_headings
    # #325 Phase 3b (Hans, 2026-05-25): Footnotes-Collector akkumuliert
    # `((Title))`-Referenzen ueber alle KI-Bodies des Trees, sodass am
    # Ende EINE Footnotes-Sektion entsteht (statt eine pro KI).
    @ref_collector   = KnowledgeMarkdown::References::Collector.new
  end

  def render
    roots = @topic.work_tree_roots.includes(:knowledge_item, children: :knowledge_item).to_a
    parts = []
    heading_counter = 0
    last_heading_path = nil
    roots.each do |node|
      if node.role == "heading"
        heading_counter += 1
        child_path = [heading_counter]
        last_heading_path = child_path
      else
        # #325 (Hans, 2026-05-25): Content-Knoten erbt fuer seine Kinder
        # den Path des juengsten vorangegangenen Heading-Geschwisters,
        # damit Sub-Headings unterhalb eines Content-Roots korrekt als
        # „1.1.\" statt „1.\" gerendert werden.
        child_path = last_heading_path || []
      end
      parts << render_node(node, @root_level, child_path)
    end
    # #325 Phase 3b: gesammelte Footnotes am Ende anhaengen.
    parts << @ref_collector.to_html if @ref_collector.any?
    parts.join("\n")
  end

  private

  # `number_path` ist die Sequenz fuer Headings — z.B. [1, 2, 3] →
  # „1.2.3.\". Content-Nodes uebernehmen den Pfad ihres Eltern-Headings
  # ohne Increment (Heading-only-Counting). Sub-Headings unter einem
  # Content-Knoten erben den Path vom naechst-vorangehenden Heading-
  # Geschwister auf gleicher Ebene.
  def render_node(node, depth, number_path)
    ki = node.knowledge_item
    return "" unless ki && ki.deleted_at.nil?

    out = +""
    if node.role == "heading"
      level   = [depth, HEADING_CAP].min
      heading = ki.title.to_s
      prefix  = (@number_headings && number_path.any?) ? "#{number_path.join('.')}. " : ""
      out << %(<h#{level}>#{ERB::Util.h(prefix + heading)}</h#{level}>\n)
      if ki.body.present?
        out << KnowledgeMarkdown.render(ki.body, item: ki, references_style: :footnote, references_collector: @ref_collector) << "\n"
      end
    else
      # content
      out << KnowledgeMarkdown.render(ki.body.to_s, item: ki, references_style: :footnote, references_collector: @ref_collector) << "\n"
    end

    heading_counter = 0
    last_heading_path = nil
    node.children.each do |child|
      if child.role == "heading"
        heading_counter += 1
        child_path = number_path + [heading_counter]
        last_heading_path = child_path
      else
        # Content erbt Path des juengsten vorangegangenen Heading-
        # Geschwisters (oder number_path, wenn noch keines).
        child_path = last_heading_path || number_path
      end
      out << render_node(child, depth + 1, child_path)
    end
    out
  end
end
