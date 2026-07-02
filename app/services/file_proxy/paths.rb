# Pfad-Helfer für FileProxy. Aus file_proxy.rb (#127) ausgelagert,
# damit `type_to_subdir`-Routing und Path-Disambiguation isoliert
# getestet und gelesen werden können.
class FileProxy
  module Paths
    module_function

    def type_to_subdir(item_type)
      case item_type.to_s
      when "note" then "notes"
      when "abstract" then "abstracts"
      when "transcript" then "transcripts"
      when "direct_quote", "indirect_quote", "quote" then "quotes"
      when "comment" then "notes"
      when "person" then "people"
      when "organization" then "organizations"
      when "doc" then "docs"
      when "image" then "images"   # #609 v3
      # Bestand-Aliase: alte Werte werden vom Indexer auf neue gemappt;
      # falls die Routing-Funktion mit alten Bezeichnungen aufgerufen wird,
      # liefern wir den neuen Pfad.
      when "ai_chat" then "abstracts"
      when "web_clip" then "transcripts"
      when "document" then "transcripts"
      else "notes"
      end
    end

    # Garantiert einen freien Dateipfad, auch wenn am gleichen Tag schon
    # ein Item mit identischem Slug angelegt wurde. Hängt im Kollisionsfall
    # einen 4-Zeichen-Suffix an (`-a1b2`). Prüft sowohl Disk als auch DB,
    # damit Re-Imports und parallele Comments nicht kollidieren.
    def unique_relative_path(subdir:, slug:, extension: ".md")
      base = "#{Date.today}-#{slug}"
      candidate = File.join("knowledge", subdir, "#{base}#{extension}")
      return candidate unless path_taken?(candidate)

      10.times do
        suffix = SecureRandom.alphanumeric(4).downcase
        candidate = File.join("knowledge", subdir, "#{base}-#{suffix}#{extension}")
        return candidate unless path_taken?(candidate)
      end
      raise "FileProxy::Paths: konnte keinen freien Dateinamen finden für #{slug}"
    end

    def path_taken?(relative_path)
      FileProxy::BASE_PATH.join(relative_path).exist? ||
        KnowledgeItem.unscoped.where(file_path: relative_path).exists?
    end
  end
end
