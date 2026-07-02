module Api
  module V1
    # POST /api/v1/tasks/:task_id/comments — Agent (oder anderer Actor)
    # postet einen Kommentar in den Task-Thread.
    #
    # #384 Phase 3c (Hans, 2026-05-27): Direkt-Cutover — schreibt jetzt
    # Reply-KIs (item_type=:reply, parent_type="Task"). API-Shape bleibt
    # kompatibel (id/task_id/actor_id/actor_name/body/created_at), `id`
    # ist jetzt aber ein UUID-String statt Integer.
    class TaskCommentsController < BaseController
      def create
        task = Task.find(params[:task_id])
        body = params.require(:body).to_s.strip
        # FileProxy.create verlangt einen Title (slugifiziert den
        # File-Pfad). Platzhalter + nachtraeglich nullen — analog
        # KnowledgeRepliesController#create / TaskRepliesController#create.
        placeholder = "Reply #{Time.current.strftime('%Y%m%d-%H%M%S')}"
        reply = FileProxy.create(
          actor:     current_actor,
          title:     placeholder,
          item_type: :reply,
          content:   body
        )
        reply.update!(
          title:         nil,
          parent_type:   "Task",
          parent_id_int: task.id,
          # #167: API-Comments sind per Default sofort veroeffentlicht —
          # der Caller (Agent) hat den Beitrag bewusst gepostet.
          published_at:  Time.current
        )
        render json: {
          data: TasksController::COMMENT_SERIALIZER.call(reply)
        }, status: :created
      end

      private

      # Kommentare hängen an Tasks — der Capability-Check geht auf die
      # Task-Resource. Wer create-Recht auf Task hat, darf auch
      # kommentieren.
      def controller_resource_type
        "Task"
      end
    end
  end
end
