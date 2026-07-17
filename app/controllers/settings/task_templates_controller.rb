class Settings::TaskTemplatesController < Settings::BaseController
  before_action :set_template, only: [:edit, :update, :destroy]

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:task_templates")
  end

  # #1054: die `render :index`-Fehlerpfade zeigten auf die seit #613
  # gelöschte index-View (500). Validierungsfehler (nur Titel-Pflicht,
  # den blockt schon das required-Feld im Browser) gehen jetzt als
  # Alert-Redirect zurück in den Stack.
  def create
    @template = TaskTemplate.new(template_params)
    if @template.save
      redirect_to settings_task_templates_path, notice: "Vorlage angelegt."
    else
      redirect_to settings_task_templates_path,
                  alert: "Vorlage nicht angelegt: #{@template.errors.full_messages.to_sentence}"
    end
  end

  # #1054: Edit als settingssub-Blade (wie Benutzer/Agenten) statt der
  # kaputten index-Render — settings_sub_spec löst das Partial auf.
  def edit
    redirect_to settings_path(stack: "list:settings,settings:task_templates,settingssub:task_templates:#{@template.id}:edit")
  end

  def update
    if @template.update(template_params)
      redirect_to settings_task_templates_path, notice: "Vorlage aktualisiert."
    else
      redirect_to settings_path(stack: "list:settings,settings:task_templates,settingssub:task_templates:#{@template.id}:edit"),
                  alert: "Nicht gespeichert: #{@template.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    @template.destroy
    redirect_to settings_task_templates_path, notice: "Vorlage geloescht."
  end

  private

  def set_template
    @template = TaskTemplate.find(params[:id])
  end

  def template_params
    params.require(:task_template).permit(:title, :description, :agent_actor_id)
  end

  # Default-Actor-Capability uebernehmen (analog Settings::BaseController) —
  # eine eigene "Setting"-Capability gibt es nicht im Permissions-Modell.
end
