# Datei-Anhang einer Aufgabe (#133). Im Gegensatz zu KIs ist ein
# Attachment task-spezifisch — Screenshots, Bug-Reports, Zwischenstände,
# die mit der Task leben und sterben. Wer einen wiederverwendbaren
# Wissensartefakt will, lädt ihn als KI hoch und verknüpft die KI per
# „Verknüpftes Wissen".
#
# Dateien liegen unter `~/miolimos/task_attachments/<task_id>/<filename>`
# — eigener Sub-Tree, damit der KI-Indexer (`~/miolimos/knowledge/…`)
# sie nicht versucht zu reindizieren.
class TaskAttachment < ApplicationRecord
  belongs_to :task
  belongs_to :uploader, class_name: "Actor"

  validates :file_path, :original_filename, presence: true

  ATTACHMENTS_SUBDIR = "task_attachments".freeze

  def self.base_path
    FileProxy::BASE_PATH.join(ATTACHMENTS_SUBDIR)
  end

  # #564: Containment-Guard (Defense-in-Depth) — der gespeicherte file_path ist
  # server-generiert, aber ein manipulierter DB-Wert (../../…) darf trotzdem
  # nie aus BASE_PATH herausführen (send_file/File.delete laufen darüber).
  def full_path
    resolved = File.expand_path(FileProxy::BASE_PATH.join(file_path))
    base     = File.expand_path(FileProxy::BASE_PATH)
    unless resolved == base || resolved.start_with?(base + File::SEPARATOR)
      raise ArgumentError, "attachment path escapes base dir"
    end
    Pathname.new(resolved)
  end

  def image?
    content_type.to_s.start_with?("image/")
  end

  def pdf?
    content_type == "application/pdf"
  end

  # Inline-Disposition für Browser-Vorschau (PDF, Bilder); Download
  # für alles andere.
  def display_disposition
    image? || pdf? ? "inline" : "attachment"
  end
end
