class FileProxy
  # #241 Plan B: Frontmatter-Merge ist jetzt strict. Nur Keys, die eine
  # DB-Spalte (oder eine bekannte Aufloesung) haben, sind erlaubt. Free-
  # Form-Felder gibt's nicht mehr — vorher schrieb das File-Frontmatter
  # auf einen Sammelhaufen, ueber den die DB nichts wusste; jetzt ist
  # die DB Source of Truth.
  module Metadata
    extend self

    # Liste der akzeptierten Frontmatter-Keys + ihre DB-Aufloesung.
    # Wert ist entweder ein Symbol (Spaltenname) oder ein Lambda
    # (knowledge_item, value) → schreibt DB.
    ALLOWED_FIELDS = {
      "type" => ->(ki, v) { ki.update!(item_type: v.to_s) },
      "bib_source" => ->(ki, v) {
        if v.is_a?(String) && v.present?
          src = Source.find_by(slug: v)
          ki.update!(bib_source_id: src&.id)
        else
          ki.update!(bib_source_id: nil)
        end
      },
      "locator_label" => :locator_label,
      "locator_value" => :locator_value,
      "provenance"    => :provenance
    }.freeze

    # Setzt einzelne Frontmatter-Felder (= DB-Spalten). Unknown Keys
    # werfen ArgumentError, damit keine stillen Frontmatter-Drifts mehr
    # entstehen.
    #
    #   FileProxy.merge_frontmatter!(actor: hans, knowledge_item: ki,
    #                                bib_source: "yt-abc123")
    def merge_frontmatter!(actor:, knowledge_item:, delete: [], **fields)
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "update")
      fields_str = fields.transform_keys(&:to_s)

      unknown = fields_str.keys - ALLOWED_FIELDS.keys
      raise ArgumentError, "Unknown frontmatter keys: #{unknown.inspect}" if unknown.any?

      fields_str.each do |key, value|
        target = ALLOWED_FIELDS[key]
        if target.is_a?(Symbol)
          knowledge_item.update!(target => value)
        else
          target.call(knowledge_item, value)
        end
      end
      Array(delete).map(&:to_s).each do |key|
        next unless ALLOWED_FIELDS.key?(key)
        target = ALLOWED_FIELDS[key]
        if target.is_a?(Symbol)
          knowledge_item.update!(target => nil)
        else
          target.call(knowledge_item, nil)
        end
      end
      knowledge_item.touch
    end
  end
end
