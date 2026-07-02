# Settings-Tab: Hinweise & Tools für den Chat-Sicherungs-Workflow.
class Settings::KnowledgeImportController < Settings::BaseController
  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:knowledge_import")
  end

  def update_prompt
    Setting.set("chat_import_prompt", params.require(:prompt))
    redirect_to settings_knowledge_import_path, notice: "Prompt-Template gespeichert."
  end

  def reset_prompt
    Setting.where(key: "chat_import_prompt").destroy_all
    redirect_to settings_knowledge_import_path, notice: "Prompt-Template auf Default zurückgesetzt."
  end

  # #672: Auftrags-Vorlage der Wikilink-Recherche (🔍 an Entitäts-Links).
  def update_research_prompt
    Setting.set("wikilink_research_prompt", params.require(:prompt))
    redirect_to settings_knowledge_import_path, notice: "Recherche-Vorlage gespeichert."
  end

  def reset_research_prompt
    Setting.where(key: "wikilink_research_prompt").destroy_all
    redirect_to settings_knowledge_import_path, notice: "Recherche-Vorlage auf Default zurückgesetzt."
  end

  # Verarbeitet die Inbox synchron — Resultat als Flash zurück.
  # Synchron, weil typische Inbox-Größen klein sind (eine Hand voll
  # Dateien). Dauert es bei Dir mal länger, später auf Active-Job
  # umstellen.
  def run_import
    results = WikiImporter.run(actor: current_actor)

    if results.empty?
      flash[:notice] = "Inbox leer — nichts zu importieren."
    else
      created  = results.count { |r| r.outcome == :created }
      appended = results.count { |r| r.outcome == :appended }
      resumed  = results.count { |r| r.outcome == :resumed }
      errors   = results.select { |r| r.outcome == :error }

      msg_parts = []
      msg_parts << "#{created} angelegt" if created > 0
      msg_parts << "#{appended} angehängt" if appended > 0
      msg_parts << "#{resumed} fertiggestellt" if resumed > 0
      msg_parts << "#{errors.size} Fehler" if errors.any?

      if errors.any?
        flash[:alert] = "Import: #{msg_parts.join(', ')}. " \
                        "Fehler: #{errors.map { |r| r.error }.join(' / ')}"
      else
        flash[:notice] = "Import: #{msg_parts.join(', ')}."
      end

      KnowledgeIndexer.run if results.any? { |r| r.outcome.in?([:created, :appended, :resumed]) }
    end

    redirect_to settings_knowledge_import_path
  end

  private

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    return "update" if action_name.in?(%w[update_prompt reset_prompt update_research_prompt reset_research_prompt])
    return "create" if action_name == "run_import"
    "read"
  end
end
