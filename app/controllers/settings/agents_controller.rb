class Settings::AgentsController < Settings::BaseController
  before_action :set_agent, only: [:show, :edit, :update, :destroy,
                                    :trigger_inbox_run,
                                    :issue_token, :revoke_token]

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
      # #1499: Kein Token mehr an der Actor-Spalte — ein neuer Agent bekommt
      # gleich ein benanntes Token. Klartext einmalig per Flash ins Agent-Blade.
      token = ApiToken.issue!(actor: @agent, name: "Standard")
      flash[:agent_api_token]      = token.token
      flash[:agent_api_token_name] = token.name
      redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}"),
                  notice: "Agent „#{@agent.name}\" angelegt. API-Token unten kopierbar — nur JETZT sichtbar."
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

  # #1499 (Hans): „Lassen sie sich einzeln zurückziehen?" — jetzt ja. Ein
  # benanntes Token je Verwendungszweck; der Klartext kommt einmalig per
  # Flash und ist danach nirgends mehr abrufbar.
  def issue_token
    name = params[:name].to_s.strip.presence || "Unbenannt"
    tage = params[:expires_in_days].to_i
    token = ApiToken.issue!(actor: @agent, name: name,
                            expires_at: (tage.positive? ? tage.days.from_now : nil))
    flash[:agent_api_token]      = token.token
    flash[:agent_api_token_name] = token.name
    redirect_to agent_blade_path, notice: "Token #{token.name.inspect} erzeugt — nur JETZT sichtbar."
  end

  # Zurückziehen statt löschen: Ein zurückgezogenes Token bleibt sichtbar,
  # mit Datum. Sonst verschwindet mit dem Eintrag auch die Antwort auf die
  # Frage, ob es dieses Token je gab.
  def revoke_token
    token = @agent.api_tokens.find(params[:token_id])
    token.revoke!
    redirect_to agent_blade_path, notice: "Token #{token.name.inspect} zurückgezogen."
  end

  # #152: Inbox-Run anstoßen. Setzt `inbox_run_requested_at`; der Agent
  # sieht das beim nächsten Heartbeat-GET als `pending_trigger: true`.
  def trigger_inbox_run
    @agent.update!(inbox_run_requested_at: Time.current)
    redirect_to settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}"),
                notice: "Trigger gesetzt — beim nächsten Heartbeat-Poll erkennt der Agent ihn."
  end

  private

  def agent_blade_path
    settings_path(stack: "list:settings,settings:agents,settingssub:agents:#{@agent.id}")
  end

  def set_agent
    @agent = AgentActor.find(params[:id])
  end

  def agent_params
    params.require(:agent_actor).permit(:name, :email, :description, :active,
                                        :workflow_instructions, :show_in_dashboard)
  end
end
