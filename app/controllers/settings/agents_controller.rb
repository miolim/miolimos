class Settings::AgentsController < Settings::BaseController
  before_action :set_agent, only: [:show, :edit, :update, :destroy,
                                    :regenerate_token, :trigger_inbox_run]

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:agents")
  end

  # #613 St.2: Einzelfenster abgelöst — als Blade im Einstellungs-Stack.
  def new
    redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:new")
  end

  def create
    @agent = AgentActor.new(agent_params)
    include_delete = ActiveModel::Type::Boolean.new.cast(params.dig(:agent_actor, :include_delete))
    if @agent.save
      @agent.grant_default_capabilities!(include_delete: include_delete)
      redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}"),
                  notice: "Agent „#{@agent.name}\" angelegt. API-Token unten kopierbar."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # #152 Phase 2: Detail-Seite mit Token (copy), Setup-Snippets für
  # tmux + Cron, Heartbeat-Status, Action-Buttons.
  def show
    redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}")
  end

  def edit
    redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}:edit")
  end

  def update
    if @agent.update(agent_params)
      redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}"), notice: "Agent gespeichert."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @agent.destroy!
    redirect_to settings_agents_path, notice: "Agent gelöscht."
  end

  # #152: Token rotieren. Alter Token wird sofort ungültig.
  def regenerate_token
    @agent.regenerate_api_token!
    redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}"),
                notice: "Neuer API-Token erzeugt — alter ist ab sofort ungültig."
  end

  # #152: Inbox-Run anstoßen. Setzt `inbox_run_requested_at`; der Agent
  # sieht das beim nächsten Heartbeat-GET als `pending_trigger: true`.
  def trigger_inbox_run
    @agent.update!(inbox_run_requested_at: Time.current)
    redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}"),
                notice: "Trigger gesetzt — beim nächsten Heartbeat-Poll erkennt der Agent ihn."
  end

  private

  def set_agent
    @agent = AgentActor.find(params[:id])
  end

  def agent_params
    params.require(:agent_actor).permit(:name, :email, :description, :active,
                                        :workflow_instructions, :show_in_dashboard)
  end
end
