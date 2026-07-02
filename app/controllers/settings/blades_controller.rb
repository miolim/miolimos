# #613 (Hans): Einstellungen als Blade-Stack. EIN Endpoint liefert jede
# Einstellungs-Seite als Stack-Card (GET /settings/blade/:page); die
# frühere Reiter-Leiste ist als Listen-Blade abgelöst (list:settings).
# Die Daten-Loader sind 1:1 aus den alten index/show-Actions der
# Einzel-Controller hierher gezogen; die Einzel-Controller behalten ihre
# Schreib-/Unterseiten-Actions und leiten ihre Index-URLs auf den Stack.
class Settings::BladesController < Settings::BaseController
  include Settings::BladeLoaders
  # Reihenfolge = Anzeige im Listen-Blade (entspricht der alten Tab-Leiste).
  # resource = Gate-Ressource — MUSS dem Gate des alten Einzel-Controllers
  # entsprechen (task_templates/ki_templates/llm_activities liefen über den
  # Settings-Base-Fallback "Actor"; eigene Ressourcen verlangten Capabilities,
  # die nie vergeben wurden → Hans' 403er, #613).
  PAGES = {
    "accounts"         => { label: "Accounts",         resource: "OauthCredential", icon: "mail" },
    "users"            => { label: "Benutzer",         resource: "Actor",           icon: "user" },
    "agents"           => { label: "Agenten",          resource: "Actor",           icon: "bot" },
    "teams"            => { label: "Teams",            resource: "Team",            icon: "users" },
    "templates"        => { label: "Themen-Vorlagen",  resource: "Topic",           icon: "folder" },
    "task_templates"   => { label: "Aufgabenvorlagen", resource: "Actor",           icon: "check" },
    "ki_templates"     => { label: "KI-Vorlagen",      resource: "Actor",           icon: "knowledge" },
    "prompt_templates" => { label: "Prompt-Vorlagen",  resource: "PromptTemplate",  icon: "sparkles" },
    "llm_activities"   => { label: "LLM-Aktivität",    resource: "Actor",           icon: "activity" },
    "knowledge_import" => { label: "Wissens-Import",   resource: "KnowledgeItem",   icon: "inbox" },
    "relations"        => { label: "Beziehungstypen",  resource: "KnowledgeItem",   icon: "link" },
    "tag_icons"        => { label: "Tag-Icons",        resource: "Actor",           icon: "tag" },
    "preferences"      => { label: "Vorlieben",        resource: "Actor",           icon: "settings" },
    "signature"        => { label: "Unterschrift",     resource: "Actor",           icon: "pencil" }
  }.freeze

  def card
    @page = params[:page].to_s
    @spec = PAGES[@page] or raise ActiveRecord::RecordNotFound
    loader = "load_#{@page}"
    send(loader) if respond_to?(loader, true)
    render partial: "settings/blades/card",
           locals: { page: @page, label: @spec[:label] }, layout: false
  end

  # #613 Stufe 2: Unterseiten-Blade (users/agents-Form, Detail-Ansichten).
  # Auflösung/Daten macht das Partial selbst (settings_sub_spec).
  def sub_card
    @page = params[:page].to_s
    raise ActiveRecord::RecordNotFound unless PAGES.key?(@page)
    render partial: "settings/blades/sub_card",
           locals: { page: @page, sub: params[:sub].to_s }, layout: false
  end

  # Listen-Blade (Einstiegs-Card) — fuer Stack-Restore/Sidebar-Append.
  def list_card
    render partial: "settings/index_list_blade", layout: false
  end

  private

  # Loader leben in Settings::BladeLoaders (auch vom Stack-Restore genutzt).



  # Gate je Seite mit der Resource der alten Einzel-Controller; die
  # Listen-Card selbst läuft als "Actor" (wie Settings-Basis).
  def controller_resource_type
    PAGES[params[:page].to_s]&.dig(:resource) || "Actor"
  end
end
