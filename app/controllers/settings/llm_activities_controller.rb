# Verlauf der LLM-getriebenen Operationen — Recherche an Absätzen,
# Inbox-AI-Transform, YouTube-Whisper/Strukturierung/Zusammenfassung.
# Liste mit Filter, Detail-View, Retry-Button bei failed.
class Settings::LlmActivitiesController < Settings::BaseController
  before_action :set_activity, only: [:show, :retry]

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:llm_activities")
  end

  # #613 St.2: Einzelfenster abgelöst — als Blade im Einstellungs-Stack.
  def show
    redirect_to settings_path(stack: "list:settings,settings:llm_activities,settingssub:llm_activities:#{@activity.id}")
  end

  # Bei failed-Activity den Original-Job erneut enqueuen. Mapping von
  # kind/source auf Job lebt im Modell, sodass neue Kinds an einer
  # einzigen Stelle ergänzt werden.
  def retry
    if @activity.retry!
      redirect_to settings_path(stack: "list:settings,settings:llm_activities,settingssub:llm_activities:#{@activity.id}"), notice: "Erneut gestartet."
    else
      redirect_to settings_path(stack: "list:settings,settings:llm_activities,settingssub:llm_activities:#{@activity.id}"),
        alert: "Quell-Datensatz nicht mehr auffindbar — Retry nicht möglich."
    end
  end

  private

  def set_activity
    @activity = LlmActivity.find(params[:id])
  end
end
