# #613 Stufe 2: Unterseiten der Einstellungen als Blades ("keine
# Einzelfenster"). Eine Sub-Blade-Spezifikation löst (page, sub) zu
# Titel + Partial + Locals auf; das sub_card-Partial lädt darüber
# SELBST (funktioniert damit identisch für Klick-Fetch und Restore).
# sub-Formate: "new" | "<id>" (Show) | "<id>:edit"
module SettingsBladesHelper
  def settings_sub_spec(page, sub)
    rid, mode =
      if sub == "new"               then [nil, :new]
      elsif sub.end_with?(":edit")  then [sub.delete_suffix(":edit"), :edit]
      else                               [sub, :show]
      end

    case page
    when "users"
      return nil if mode == :show
      user = mode == :new ? HumanActor.new(active: true) : HumanActor.find(rid)
      { title:   mode == :new ? "Neuer Benutzer" : "Benutzer: #{user.name}",
        icon:    "user", partial: "settings/users/form", locals: { user: user } }
    when "agents"
      agent = mode == :new ? AgentActor.new(active: true) : AgentActor.find(rid)
      if mode == :show
        { title: "Agent: #{agent.name}", icon: "bot",
          partial: "settings/blades/agent_show", locals: { agent: agent } }
      else
        { title: mode == :new ? "Neuer Agent" : "Agent bearbeiten: #{agent.name}",
          icon: "bot", partial: "settings/agents/form", locals: { agent: agent } }
      end
    when "llm_activities"
      return nil unless mode == :show
      activity = LlmActivity.find(rid)
      { title: "LLM-Aktivität ##{activity.id}", icon: "activity",
        partial: "settings/blades/llm_activity_show", locals: { activity: activity } }
    when "prompt_templates"
      tpl = mode == :new ? PromptTemplate.new : PromptTemplate.find_by!(slug: rid)
      if mode == :show
        { title: tpl.name, icon: "sparkles",
          partial: "settings/blades/prompt_template_show", locals: { template: tpl } }
      else
        { title: mode == :new ? "Neue Prompt-Vorlage" : "Vorlage: #{tpl.name}",
          icon: "sparkles", partial: "prompt_templates/form", locals: { template: tpl } }
      end
    when "task_templates"
      # #1054: nur Edit — Anlegen läuft über die Inline-Form im Bereichs-
      # Blade. Vorher rendete die Edit-Action die seit #613 gelöschte
      # index-View (500 bei jedem Bearbeiten-Klick).
      return nil unless mode == :edit
      tpl = TaskTemplate.find(rid)
      { title: "Vorlage: #{tpl.title}", icon: "check",
        partial: "settings/task_templates/form",
        locals: { template: tpl, agent_actors: AgentActor.order(:name) } }
    end
  end
end
