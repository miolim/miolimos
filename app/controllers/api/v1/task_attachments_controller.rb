require "fileutils"

module Api
  module V1
    # #182: API-Bearer-Pfad für Task-Attachments — Agenten können
    # Screenshots/PDFs via WebFetch mit Authorization-Header lesen.
    # Streamt dieselbe Datei wie der Web-Pfad, nur ohne Session-Auth.
    # #774 (Hans): + create — Agenten können Dateien (z.B. generierte
    # Bilder/PDFs) an Aufgaben anhängen. Speicher-Logik wie im Web-Pfad
    # (TaskAttachmentsController#create).
    class TaskAttachmentsController < BaseController
      def create
        task = Task.find(params[:task_id])
        file = params[:file]
        if file.blank?
          render json: { error: "file is required (multipart field 'file')", code: "missing_file" },
                 status: :unprocessable_entity and return
        end

        target_dir = TaskAttachment.base_path.join(task.id.to_s)
        FileUtils.mkdir_p(target_dir)
        original = file.original_filename.to_s
        safe     = original.gsub(/[^\w.\-]+/, "_")
        stored   = "#{SecureRandom.hex(4)}-#{safe}"
        full     = target_dir.join(stored)
        File.open(full, "wb") do |f|
          file.rewind if file.respond_to?(:rewind)
          IO.copy_stream(file, f)
        end

        rel = full.relative_path_from(FileProxy::BASE_PATH).to_s
        att = task.attachments.create!(
          uploader:          current_actor,
          file_path:         rel,
          original_filename: original,
          content_type:      file.content_type.presence,
          byte_size:         file.size
        )
        render json: { data: {
          id: att.id, task_id: task.id, original_filename: att.original_filename,
          content_type: att.content_type, byte_size: att.byte_size,
          url: api_v1_task_attachment_path(task, att)
        } }, status: :created
      end

      def show
        task       = Task.find(params[:task_id])
        attachment = task.attachments.find(params[:id])
        full       = attachment.full_path
        unless File.exist?(full)
          render json: { error: "not found" }, status: :not_found and return
        end
        send_file full,
                  type:        attachment.content_type.presence || "application/octet-stream",
                  disposition: attachment.display_disposition,
                  filename:    attachment.original_filename
      end

      private

      def controller_resource_type
        "Task"
      end

      def controller_action_to_capability
        action_name == "create" ? "update" : "read"
      end
    end
  end
end
