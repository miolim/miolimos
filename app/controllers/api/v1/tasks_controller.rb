module Api
  module V1
    class TasksController < BaseController
      TASK_SERIALIZER = ->(t) do
        {
          id: t.id, title: t.title, description: t.description,
          status: t.status, priority: t.priority,
          due_date: t.due_date, completed_at: t.completed_at,
          assignee_id: t.assignee_id, creator_id: t.creator_id,
          parent_id: t.parent_id, communication_id: t.communication_id,
          wip_actor_id: t.wip_actor_id,
          tags: Array(t.tags),
          published_at: t.published_at,
          created_at: t.created_at, updated_at: t.updated_at
        }
      end

      # #384 Phase 3c (Hans, 2026-05-27): Comments-API serialisiert
      # jetzt Reply-KIs (item_type=:reply, parent_type="Task"). Shape
      # bleibt kompatibel zum bisherigen TaskComment-Output (id, task_id,
      # actor_id, actor_name, body, created_at) — `id` ist jetzt aber
      # ein UUID-String statt Integer (Hans-Spec „keine Schirme\",
      # direkt umstellen).
      COMMENT_SERIALIZER = ->(r) do
        {
          id:         r.uuid,
          task_id:    r.parent_id_int,
          actor_id:   r.creator_id,
          actor_name: r.creator&.name,
          body:       r.body,
          created_at: r.published_at || r.created_at
        }
      end

      def index
        # #167: API-Inbox sieht nur veröffentlichte Aufgaben. Drafts
        # bleiben unsichtbar, bis Hans (oder ein anderer Web-User) sie
        # explizit freigibt.
        scope = visible(Task).published
        scope = scope.where(status:   params[:status])   if params[:status].present?
        scope = scope.where(priority: params[:priority]) if params[:priority].present?
        scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?

        # tags-Filter: ?tag=bug → enthält "bug" (Postgres-Array-Operator).
        if params[:tag].present?
          scope = scope.where("tags && ARRAY[?]::varchar[]", Array(params[:tag]))
        end

        if params[:topic_id].present?
          scope = scope.joins(:task_topics).where(task_topics: { topic_id: params[:topic_id] })
                       .order("task_topics.position ASC")
        else
          scope = scope.order(:id)
        end
        render_collection(scope, serializer: TASK_SERIALIZER)
      end

      def show
        task = visible(Task).includes(:attachments).find(params[:id])
        # #384 Phase 3c (Hans, 2026-05-27): Reply-KIs sind jetzt die
        # universelle Beitrags-Form. `task.replies` liefert
        # KnowledgeItem-Records mit item_type=:reply.
        published_replies = task.replies.where.not(published_at: nil).includes(:creator)
        render json: {
          data: TASK_SERIALIZER.call(task),
          comments: published_replies.map { |r| COMMENT_SERIALIZER.call(r) },
          attachments: task.attachments.map { |a|
            {
              id: a.id,
              filename: a.original_filename,
              content_type: a.content_type,
              byte_size: a.byte_size,
              # API-Bearer-Pfad: streamt das Original-File mit Token-
              # Auth. WebFetch kann es mit Authorization-Header lesen.
              url: "#{request.base_url}/api/v1/tasks/#{task.id}/attachments/#{a.id}",
              created_at: a.created_at
            }
          }
        }
      end

      def create
        # #167: API-Creates sind per Default sofort veröffentlicht — der
        # Caller (Agent, Browser-Add-on, External Trigger) hat den Task
        # bewusst angelegt. Drafts existieren nur über die Web-UI.
        attrs = permitted_attrs.merge(creator: current_actor)
        attrs[:published_at] ||= Time.current
        task = Task.create!(attrs)
        render_one(task, serializer: TASK_SERIALIZER, status: :created)
      end

      def update
        task = Task.find(params[:id])
        task.update!(permitted_attrs)
        render_one(task, serializer: TASK_SERIALIZER)
      end

      def destroy
        Task.find(params[:id]).destroy!
        head :no_content
      end

      private

      def permitted_attrs
        params.permit(:title, :description, :status, :priority, :due_date,
                      :completed_at, :assignee_id, :parent_id, :communication_id,
                      :wip_actor_id,
                      tags: [])
      end
    end
  end
end
