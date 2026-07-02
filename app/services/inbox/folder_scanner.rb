require "pathname"
require "fileutils"

module Inbox
  # Scant das ~/miolimos/inbox/-Verzeichnis nach .md-Dateien und legt
  # für jede ein InboxItem an (Status: pending). Datei wird nach
  # ~/miolimos/inbox/.processed/ verschoben, damit sie nicht doppelt
  # eingelesen wird. Beim "Run" des Processors greift MarkdownToKi
  # auf inbox_item.external_path zu.
  #
  # Ersetzt das alte WikiImporter.run, das direkt KIs anlegte.
  # WikiImporter bleibt als Parser-Utility (Light-Header, Lookup)
  # erhalten und wird vom MarkdownToKi-Processor weiter verwendet.
  class FolderScanner
    def self.run(actor:)
      new(actor: actor).run
    end

    def initialize(actor:, inbox: WikiImporter::INBOX_PATH)
      @actor = actor
      @inbox = Pathname.new(inbox)
    end

    def run
      ensure_inbox_dir!
      created = []
      @inbox.glob("*.md").sort.each do |file|
        item = create_inbox_item(file)
        next unless item
        move_to_holding(file, item)
        created << item
      end
      created
    end

    private

    def ensure_inbox_dir!
      FileUtils.mkdir_p(@inbox) unless @inbox.exist?
      FileUtils.mkdir_p(@inbox.join(".processed"))
      gi = @inbox.join(".gitignore")
      File.write(gi, "*\n!.gitignore\n") unless gi.exist?
    end

    def create_inbox_item(file)
      raw = file.read
      InboxItem.create!(
        creator:        @actor,
        source_kind:    "markdown",
        external_path:  file.to_s,
        raw_content:    raw,
        title:          file.basename(".md").to_s,
        status:         "pending"
      )
    rescue => e
      Rails.logger.warn("Inbox::FolderScanner: skip #{file}: #{e.class} #{e.message}")
      nil
    end

    # Datei in .processed/ schieben — die InboxItem-DB-Zeile hält
    # `raw_content` plus Pfad; verarbeitet wird gegen raw_content,
    # daher ist die Datei-Verschiebung sicher.
    def move_to_holding(file, item)
      target_dir = @inbox.join(".processed", Date.current.iso8601)
      FileUtils.mkdir_p(target_dir)
      target = target_dir.join(file.basename)
      FileUtils.mv(file, target)
      item.update_column(:external_path, target.to_s)
    end
  end
end
