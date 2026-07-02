# #655 (Hans, 2026-06-12): Selektierten Namen im Body als Personen-
# Wikilink auszeichnen — `Audrey Tang` → `[[@Audrey Tang]]`. Der
# `[[@…]]`-Resolver findet bestehende Personen-/Org-KIs per Titel/Alias
# (case-insensitive); fehlt die Person, rendert der Link als „missing"
# und der Researcher kann sie über den Entitäten-Import anlegen.
# Block-Findung und Read/Write wie BodyHighlightWrapper (KI + Task).
class BodyPersonWrapper
  class Error < StandardError; end

  def self.call(item:, actor:, anchor:, selected_text:)
    new(item: item, actor: actor, anchor: anchor, selected_text: selected_text).call
  end

  def initialize(item:, actor:, anchor:, selected_text:)
    @item   = item
    @actor  = actor
    @anchor = anchor.to_s
    @text   = selected_text.to_s.strip
  end

  def call
    raise Error, "Keine Auswahl übergeben" if @text.blank?
    raise Error, "Auswahl enthält Zeichen, die in Wikilinks nicht erlaubt sind" if @text.match?(/[\[\]|#^\n]/)

    body  = read_body
    raise Error, "Body leer" if body.blank?
    raise Error, "„#{@text}“ ist hier schon ein Wikilink" if body.include?("[[@#{@text}") || body.include?("[[#{@text}")

    # Whitespace-tolerant: die DOM-Selektion hat Spaces, die Quelle kann
    # an derselben Stelle umgebrochen sein.
    needle = Regexp.new(@text.split(/\s+/).map { |w| Regexp.escape(w) }.join('\s+'))

    lines = body.lines
    idxs  = locate_block(body)
    if idxs
      block_text = lines[idxs.first..idxs.last].join
      if (m = block_text.match(needle))
        new_block = block_text.sub(needle) { "[[@#{@text}]]" }
        new_body  = (lines[0...idxs.first] + [new_block] + lines[(idxs.last + 1)..].to_a).join
        write_body(new_body)
        return new_body
      end
    end

    # #655 v2: DOM-Block-Nummern (block-N) und Quell-Block-Zählung können
    # auseinanderlaufen (Listen/Überschriften zählen unterschiedlich) —
    # dann im GANZEN Body suchen; bei genau EINEM Treffer ist das sicher.
    matches = body.to_enum(:scan, needle).map { Regexp.last_match.begin(0) }
    case matches.size
    when 0
      raise Error, "Auswahl nicht gefunden (enthält sie Formatierung?)"
    when 1
      new_body = body.sub(needle) { "[[@#{@text}]]" }
      write_body(new_body)
      new_body
    else
      raise Error, "„#{@text}“ kommt #{matches.size}× vor und der Block ließ sich nicht eindeutig zuordnen — bitte das gewünschte Vorkommen zuerst kurz highlighten (bekommt einen Anker) und es dann erneut versuchen."
    end
  end

  private

  # Wie BodyHighlightWrapper#locate_block: `block-N` oder stabiler ^id.
  # nil ist ok — der Aufrufer fällt dann auf die Ganz-Body-Suche zurück.
  def locate_block(body)
    anchor_blocks = KnowledgeBlockAnchor.new(@item, actor: @actor).send(:block_line_indices, body)
    if @anchor =~ /\Ablock-(\d+)\z/i
      n = Regexp.last_match(1).to_i
      anchor_blocks[n - 1]
    else
      anchor_blocks.find do |idxs|
        idxs.map { |i| body.lines[i] }.join.match?(/\^#{Regexp.escape(@anchor)}(\s|$)/)
      end
    end
  rescue StandardError
    nil
  end

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
