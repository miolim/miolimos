# #633 (Hans, 2026-06-12): E-Mail-Anhang in die Inbox übernehmen.
# Holt die Bytes via Gmail-API (Credential der Kommunikation), legt die
# Datei im Inbox-Upload-Ordner ab und erzeugt ein InboxItem mit
# Provenienz (payload.communication_id/attachment_index) + geerbten
# Topics der Mail. Gate: InboxItem.create (die Mutation).
class Communications::AttachmentsController < ApplicationController
  include StackRedirects

  # POST /communications/:communication_id/attachments/import?index=N
  def create
    comm = Communication.visible_to(current_actor).find(params[:communication_id])
    idx  = params[:index].to_i
    meta = comm.attachments[idx]
    raise ActiveRecord::RecordNotFound, "Anhang #{idx} nicht gefunden" unless meta

    credential = comm.oauth_credential
    unless credential
      redirect_back fallback_location: communications_path,
                    alert: "Kommunikation hat kein OAuth-Credential — Anhang nicht abrufbar." and return
    end

    # Doppel-Import abfangen (Button ist dann eh weg, aber Direkt-POSTs).
    if (existing = imported_item(comm, idx))
      redirect_to inbox_items_path(stack: "list:inbox_items,inboxitem:#{existing.id}"),
                  notice: "Anhang ist schon in der Inbox." and return
    end

    bytes = GmailSync.fetch_attachment(credential, comm.external_id, meta[:attachment_id])
    item  = store_as_inbox_item!(comm, idx, meta, bytes)

    if (stay = stay_in_stack_redirect_to("inboxitem:#{item.id}"))
      redirect_to stay, notice: "Anhang in die Inbox übernommen."
    else
      redirect_to inbox_items_path(stack: "list:inbox_items,inboxitem:#{item.id}"),
                  notice: "Anhang in die Inbox übernommen."
    end
  rescue GmailSync::SyncError => e
    redirect_back fallback_location: communications_path,
                  alert: "Anhang-Abruf fehlgeschlagen: #{e.message.truncate(120)}"
  end

  private

  def imported_item(comm, idx)
    InboxItem.where("payload->>'communication_id' = ?", comm.id.to_s)
             .where("payload->>'attachment_index' = ?", idx.to_s)
             .first
  end

  # Ablage wie InboxItemsController#store_uploaded_file!: Upload-Ordner
  # der Inbox, SecureRandom-Präfix gegen Kollisionen.
  def store_as_inbox_item!(comm, idx, meta, bytes)
    dir = Pathname.new(WikiImporter::INBOX_PATH).join(".uploads", Date.current.iso8601)
    FileUtils.mkdir_p(dir)
    safe_name = "#{SecureRandom.hex(4)}-#{meta[:filename].gsub(/[^\w.\-]+/, '_')}"
    target    = dir.join(safe_name)
    File.binwrite(target, bytes)

    is_pdf = meta[:filename].to_s.downcase.end_with?(".pdf") ||
             meta[:mime_type] == "application/pdf"
    item = InboxItem.create!(
      creator:       current_actor,
      source_kind:   is_pdf ? "pdf_upload" : "upload",
      external_path: target.to_s,
      title:         File.basename(meta[:filename], ".*"),
      payload:       { "original_filename" => meta[:filename],
                       "content_type"      => meta[:mime_type],
                       "communication_id"  => comm.id,
                       "attachment_index"  => idx }
    )
    # Provenienz-Kette: Themen der Mail erben — die Verarbeitungs-
    # Ergebnisse (KIs/Tasks) erben sie via ProcessorBase weiter.
    comm.topics.each { |t| InboxItemTopic.find_or_create_by!(inbox_item: item, topic: t) }
    item
  end

  def controller_resource_type
    "InboxItem"
  end

  def controller_action_to_capability
    "create"
  end
end
