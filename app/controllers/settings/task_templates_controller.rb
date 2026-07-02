class Settings::TaskTemplatesController < Settings::BaseController
  before_action :set_template, only: [:edit, :update, :destroy]

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:task_templates")
  end

  def create
    @template = TaskTemplate.new(template_params)
    if @template.save
      redirect_to settings_task_templates_path, notice: "Vorlage angelegt."
    else
      @templates = TaskTemplate.order(:title)
      @agent_actors = AgentActor.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @templates = TaskTemplate.order(:title)
    @agent_actors = AgentActor.order(:name)
    render :index
  end

  def update
    if @template.update(template_params)
      redirect_to settings_task_templates_path, notice: "Vorlage aktualisiert."
    else
      @templates = TaskTemplate.order(:title)
      @agent_actors = AgentActor.order(:name)
      render :index, status: :unprocessable_entity
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
