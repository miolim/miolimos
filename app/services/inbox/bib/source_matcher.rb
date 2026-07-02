module Inbox
  module Bib
    # Findet eine existierende Source, die zum Pipeline-Ergebnis passt
    # (#65 Phase C). Reihenfolge:
    #
    #   1. Identifier-Match (DOI/ISBN, case-insensitive)
    #   2. Title-+First-Author-Family-Match (parameterized)
    #
    # Gibt die Source zurück oder nil, wenn keine passt. Der Aufrufer
    # entscheidet, ob er die Source-Felder updatet oder unangetastet
    # lässt — der Sinn von Phase C ist gerade, eine händisch gepflegte
    # Source NICHT zu überschreiben, sondern bloß ein weiteres KI als
    # Anhang einzuhängen.
    module SourceMatcher
      def self.find(result)
        find_by_identifier(result[:identifier]) || find_by_title_author(result)
      end

      def self.find_by_identifier(ident)
        return nil if ident.blank?
        return nil if ident[:value].to_s.strip.empty?
        Source.joins(:source_identifiers)
              .where(source_identifiers: { scheme: ident[:scheme] })
              .where("lower(source_identifiers.value) = ?", ident[:value].to_s.strip.downcase)
              .first
      end

      def self.find_by_title_author(result)
        title_key = title_key(result[:title])
        return nil if title_key.blank?
        family = first_author_family(result)
        return nil if family.blank?

        # Postgres-spezifisch: lower+regexp_replace approximiert parameterize.
        # Wir holen erst alle Title-Matches, filtern Family in Ruby gegen
        # die source_creators-KIs (begrenzt auf 10, kein Hot-Path).
        candidates = Source.where(
          "trim(both '-' from regexp_replace(lower(title), '[^a-z0-9]+', '-', 'g')) = ?", title_key
        ).limit(10).to_a

        candidates.find do |s|
          first_creator = s.source_creators.order(:position, :id).first
          ki = first_creator&.knowledge_item
          ki && ki.last_name.to_s.parameterize == family
        end
      end

      def self.title_key(title)
        title.to_s.parameterize
      end

      def self.first_author_family(result)
        first = Array(result[:authors]).first
        return "" if first.blank?
        (first[:family] || first["family"]).to_s.parameterize
      end
    end
  end
end
