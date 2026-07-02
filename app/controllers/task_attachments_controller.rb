require "fileutils"

# Task-Anhänge (#133). Upload, Inline-Stream und Löschen. Dateien liegen
# unter `~/miolimos/task_attachments/<task_id>/<uuid>-<filename>` —
# UUID-Prefix vermeidet Namens-Kollisionen bei zwei Screenshots mit
# identischem Original-Dateinamen.
class TaskAttachmentsController < ApplicationController
  before_action :set_task,        only: [:create, :show, :destroy]
  before_action :set_attachment,  only: [:show, :destroy]

  def create
    file = params[:file]
    if file.blank?
      redirect_back fallback_location: task_path(@task), alert: "Keine Datei ausgewählt." and return
    end

    target_dir = TaskAttachment.base_path.join(@task.id.to_s)
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
    attachment = @task.attachments.create!(
      uploader:          current_actor,
      file_path:         rel,
      original_filename: original,
      content_type:      file.content_type.presence,
      byte_size:         file.size
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("task_attachments_#{@task.id}",
          partial: "tasks/attachments", locals: { task: @task })
      end
      format.html { redirect_to task_path(@task), notice: "Datei '#{attachment.original_filename}' hochgeladen." }
    end
  end

  # GET /tasks/:task_id/attachments/:id — Inline-Stream (Bilder, PDF)
  # bzw. Attachment-Download (alles andere).
  def show
    full = @attachment.full_path
    raise ActionController::RoutingError, "not found" unless File.exist?(full)
    send_file full,
      type:        @attachment.content_type.presence || "application/octet-stream",
      disposition: @attachment.display_disposition,
      filename:    @attachment.original_filename
  end

  def destroy
    full = @attachment.full_path
    File.delete(full) if File.exist?(full)
    @attachment.destroy!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("task_attachments_#{@task.id}",
          partial: "tasks/attachments", locals: { task: @task.reload })
      end
      format.html { redirect_to task_path(@task), notice: "Anhang gelöscht." }
    end
  end

  private

  def set_task
    @task = Task.find(params[:task_id])
  end

  def set_attachment
    @attachment = @task.attachments.find(params[:id])
  end

  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    case action_name
    when "show"            then "read"
    when "create"          then "update"
    when "destroy"         then "update"
    else super
    end
  end
end
