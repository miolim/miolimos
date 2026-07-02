# #634: Datei-Upload → InboxItem, extrahiert aus InboxItemsController —
# der Share-Endpoint (Android-Share-Target) braucht denselben Pfad.
# Ablage im Inbox-Upload-Ordner mit SecureRandom-Präfix gegen
# Filename-Kollisionen; PDFs erkennen wir am Suffix/Content-Type und
# mappen auf source_kind=pdf_upload, alles andere bleibt "upload".
module InboxItemUploads
  extend ActiveSupport::Concern

  private

  def store_uploaded_file!(file)
    dir = Pathname.new(WikiImporter::INBOX_PATH).join(".uploads", Date.current.iso8601)
    FileUtils.mkdir_p(dir)
    safe_name = "#{SecureRandom.hex(4)}-#{file.original_filename.gsub(/[^\w.\-]+/, '_')}"
    target    = dir.join(safe_name)
    File.open(target, "wb") do |f|
      file.tempfile.rewind if file.tempfile.respond_to?(:rewind)
      IO.copy_stream(file.tempfile, f)
    end
    is_pdf = file.original_filename.to_s.downcase.end_with?(".pdf") ||
             file.content_type.to_s == "application/pdf"
    InboxItem.create!(
      creator:       current_actor,
      source_kind:   is_pdf ? "pdf_upload" : "upload",
      external_path: target.to_s,
      title:         File.basename(file.original_filename, ".*"),
      payload:       { "original_filename" => file.original_filename,
                       "content_type"      => file.content_type.to_s }
    )
  end
end
