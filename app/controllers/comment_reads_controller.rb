# #211: Markiert TaskComments fuer current_actor als gelesen — aus der
# Dashboard-Sektion „Ungelesene Kommentare". Vorher hat
# TasksController#show das automatisch erledigt; das war zu aggressiv,
# weil ein einzelner Task-Visit ALLE folgenden Comments verschwinden
# liess. Jetzt geht das nur noch explizit ueber Buttons.
#
# Akzeptiert:
#   POST /comment_reads { comment_id: 42 }           — eines
#   POST /comment_reads { comment_ids: [42, 43, 44] } — bulk
#
# Antwort: Turbo-Stream, das die markierten Eintraege aus der
# Dashboard-Sektion entfernt.
class CommentReadsController < ApplicationController
  def create
    ids = Array(params[:comment_ids]).map(&:to_i) << params[:comment_id].to_i
    ids = ids.reject(&:zero?).uniq
    return head :no_content if ids.empty?

    now = Time.current
    rows = ids.map { |cid| { actor_id: current_actor.id, task_comment_id: cid,
                              read_at: now, created_at: now, updated_at: now } }
    CommentRead.insert_all(rows, unique_by: %i[actor_id task_comment_id])

    respond_to do |format|
      format.turbo_stream do
        # Pro Comment ein Remove-Stream. Der Wrapper im Partial hat
        # die ID `unread_comment_<id>`. Wenn das letzte Element einer
        # Task-Gruppe entfernt wird, koennte zusaetzlich das Task-Item
        # leer dastehen — das nehmen wir vorerst in Kauf, kommt erst
        # beim naechsten Dashboard-Refresh weg.
        streams = ids.map { |id| turbo_stream.remove("unread_comment_#{id}") }
        render turbo_stream: streams
      end
      format.json { render json: { marked: ids.size } }
    end
  end

  private

  # Comment-Reads sind eine Variante von „Task lesen" — der Caller
  # quittiert, dass er einen Comment des Tasks gesehen hat. Aelter
  # angelegter resource_type war "TaskComment", aber dafuer hat
  # niemand Capabilities (es gibt keine TaskComment-Caps in der DB).
  # Daher: gate gegen Task wie auch TaskCommentsController es macht.
  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    # Eigener Lese-Status auf Comments markieren ist semantisch ein
    # Read — wer Tasks lesen darf, darf auch quittieren, dass er einen
    # Comment gesehen hat. Vermeidet, dass Hans (oder andere User mit
    # nur Task-read) den Button-Klick wegen Forbidden nicht ausloesen
    # koennen (#211-Folge-Bug).
    return "read" if action_name == "create"
    super
  end
end
