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
    "agents"           => { label: "Agenten",          resource: "Actor",           icon: "bot", admin: true },
    "teams"            => { label: "Teams",            resource: "Team",            icon: "users" },
    "templates"        => { label: "Themen-Vorlagen",  resource: "Topic",           icon: "folder" },
    "task_templates"   => { label: "Aufgabenvorlagen", resource: "Actor",           icon: "check" },
    "ki_templates"     => { label: "Eintrags-Vorlagen", resource: "Actor",          icon: "knowledge" },
    "prompt_templates" => { label: "Prompt-Vorlagen",  resource: "PromptTemplate",  icon: "sparkles" },
    "document_templates" => { label: "Dokumentvorlagen", resource: "KnowledgeItem",  icon: "file_text" },
    "llm_activities"   => { label: "LLM-Aktivität",    resource: "Actor",           icon: "activity" },
    # #1660: Token-Verbrauch der Agenten-Sitzungen (aus den Protokollen).
    "agent_usage"      => { label: "Token-Verbrauch",  resource: "Actor",           icon: "banknote" },
    "knowledge_import" => { label: "Wissens-Import",   resource: "KnowledgeItem",   icon: "inbox" },
    "relations"        => { label: "Beziehungstypen",  resource: "KnowledgeItem",   icon: "link" },
    "tag_icons"        => { label: "Tag-Icons",        resource: "Actor",           icon: "tag" },
    "preferences"      => { label: "Vorlieben",        resource: "Actor",           icon: "settings" },
    "signature"        => { label: "Unterschrift",     resource: "Actor",           icon: "pencil" },
    # #1051: 2FA-Selbstverwaltung (TOTP) des eingeloggten Nutzers.
    "security"         => { label: "Sicherheit",       resource: "Actor",           icon: "shield" },
    "internetmarke"    => { label: "Frankierung",      resource: "Actor",           icon: "mail" }
  }.freeze

  # #1675: DIE eine Stelle für „darf dieser Nutzer diese Einstellungs-Seite
  # sehen?" — gefragt vom Card-Endpoint hier, vom Stack-Restore
  # (BladeStackLoader) und von der Bereichs-Liste. Seiten mit `admin: true`
  # gehören Admins. Das Recht „Actor" taugt dafür nicht, das hat jeder Mensch.
  def self.page_visible?(page, actor)
    spec = PAGES[page.to_s] or return false
    !spec[:admin] || actor&.admin? || false
  end

  # Unterseiten erben die Regel ihrer Seite. Sonderfall Benutzer: Die Seite
  # sehen alle (mit sich selbst darin), aber ein fremdes Profil oder „neu"
  # öffnet nur ein Admin.
  def self.sub_visible?(page, sub, actor)
    return false unless page_visible?(page, actor)
    return true  unless page.to_s == "users"
    actor&.admin? || sub.to_s == "#{actor&.id}:edit"
  end

  def card
    @page = params[:page].to_s
    @spec = PAGES[@page] or raise ActiveRecord::RecordNotFound
    require_admin! unless self.class.page_visible?(@page, current_actor)
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
    require_admin! unless self.class.sub_visible?(@page, params[:sub], current_actor)
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
