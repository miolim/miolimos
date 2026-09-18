# #1660: Liest die Sitzungsprotokolle der Agenten (Claude Code schreibt je
# Sitzung eine JSONL-Datei) und verdichtet den Token-Verbrauch nach Tag,
# Projekt, Aufgabe und Modell.
#
# Zuordnung zur Aufgabe: Jede Aufgabe beginnt mit einer Auslöser-Zeile
# („Inbox-Check … [Auslöser: … Aufgabe #1660 …]"). Alles, was danach bis zur
# nächsten Auslöser-Zeile verbraucht wird, gehört zu dieser Aufgabe.
#
# Idempotent: Derselbe Schlüssel wird ersetzt, nicht addiert — ein zweiter
# Lauf über dieselben Tage ändert nichts.
class AgentUsage
  class Import
    AUSLOESER = /Auslöser|Inbox-Check/
    NUMMER    = /Aufgabe\s+#?(\d{3,5})|#(\d{3,5})\b/

    def self.basis_pfad
      Pathname.new(ENV.fetch("CLAUDE_PROJECTS_DIR", File.expand_path("~/.claude/projects")))
    end

    # tage: wie weit zurück gelesen wird. Ältere Zeilen überspringt der
    # Parser; Dateien, die seitdem nicht angefasst wurden, gar nicht erst.
    def self.call(tage: 45, basis: basis_pfad)
      new(tage: tage, basis: Pathname.new(basis)).call
    end

    def initialize(tage:, basis:)
      @grenze = Date.current - tage + 1
      @basis  = basis
    end

    def call
      return { dateien: 0, zeilen: 0, geschrieben: 0 } unless @basis.directory?

      eimer = Hash.new { |h, k| h[k] = Hash.new(0) }
      dateien = 0
      Dir.glob(@basis.join("*", "*.jsonl")).sort.each do |pfad|
        next if File.mtime(pfad).to_date < @grenze
        dateien += 1
        lese_datei(pfad, eimer)
      end

      geschrieben = schreibe(eimer)
      { dateien: dateien, zeilen: eimer.size, geschrieben: geschrieben }
    end

    private

    def lese_datei(pfad, eimer)
      projekt = File.basename(File.dirname(pfad))
      aufgabe = nil
      File.foreach(pfad) do |zeile|
        d = JSON.parse(zeile) rescue nil
        next unless d.is_a?(Hash)

        case d["type"]
        when "user"
          text = text_von(d)
          aufgabe = nummer_aus(text) if text.match?(AUSLOESER)
        when "assistant"
          tag = tag_von(d)
          next if tag.nil? || tag < @grenze
          nachricht = d["message"]
          next unless nachricht.is_a?(Hash)
          verbrauch = nachricht["usage"]
          next unless verbrauch.is_a?(Hash)

          e = eimer[[tag, projekt, aufgabe, nachricht["model"].to_s.presence || "?"]]
          e[:antworten]            += 1
          e[:input_tokens]         += verbrauch["input_tokens"].to_i
          e[:cache_creation_tokens] += verbrauch["cache_creation_input_tokens"].to_i
          e[:cache_read_tokens]    += verbrauch["cache_read_input_tokens"].to_i
          e[:output_tokens]        += verbrauch["output_tokens"].to_i
        end
      end
    end

    def text_von(d)
      inhalt = d.dig("message", "content")
      case inhalt
      when String then inhalt
      when Array  then inhalt.filter_map { |t| t["text"] if t.is_a?(Hash) && t["type"] == "text" }.join(" ")
      else ""
      end
    end

    def nummer_aus(text)
      m = NUMMER.match(text)
      m && (m[1] || m[2])
    end

    def tag_von(d)
      Time.iso8601(d["timestamp"].to_s).to_date
    rescue ArgumentError, TypeError
      nil
    end

    # Ersetzen statt addieren: Ein Lauf liefert für jeden berührten Tag den
    # vollständigen Stand.
    def schreibe(eimer)
      return 0 if eimer.empty?
      jetzt = Time.current
      zeilen = eimer.map do |(tag, projekt, aufgabe, model), werte|
        { tag: tag, projekt: projekt, aufgabe: aufgabe, model: model,
          antworten: werte[:antworten], input_tokens: werte[:input_tokens],
          cache_creation_tokens: werte[:cache_creation_tokens],
          cache_read_tokens: werte[:cache_read_tokens],
          output_tokens: werte[:output_tokens],
          created_at: jetzt, updated_at: jetzt }
      end
      zeilen.each_slice(500) do |teil|
        AgentUsage.upsert_all(teil, unique_by: "index_agent_usages_on_schluessel")
      end
      zeilen.size
    end
  end
end
