# #1036 (Hans): Sichtbare Verwaltung der Dokument- & E-Mail-Vorlagen.
# Eine Vorlage IST eine Notiz-KI mit Tag "vorlage:<typ>" (bestehender
# Mechanismus aus #766) — dieser Controller legt solche KIs an bzw.
# nimmt ihnen nur den Vorlagen-Tag weg. Der Vorlagentext wird in der
# normalen KI-Card gepflegt (Editor, Versionierung, Wikilinks).
class Settings::DocumentTemplatesController < Settings::BaseController
  # Typen mit Vorlagen-Unterstützung: die Dokument-Kinds (Document#kind)
  # + "email" für die Compose-Popover-Vorlagen (#1027).
  KINDS = %w[brief nda lastschrift email].freeze

  def index
    redirect_to settings_path(stack: "list:settings,settings:document_templates")
  end

  def create
    kind  = params[:kind].to_s
    title = params[:title].to_s.strip
    unless KINDS.include?(kind)
      return redirect_to settings_document_templates_path, alert: t("settings.document_templates.bad_kind")
    end
    if title.blank?
      return redirect_to settings_document_templates_path, alert: t("settings.document_templates.title_missing")
    end
    ki = FileProxy.create(actor: current_actor, title: title, item_type: :note,
                          content: "", tags: ["vorlage:#{kind}"])
    # Direkt die neue Vorlagen-KI im Stack öffnen, damit der Text sofort
    # eingetragen werden kann.
    redirect_to settings_path(stack: "list:settings,settings:document_templates,#{ki.uuid}"),
                notice: t("settings.document_templates.created", title: title)
  end

  # destroy = Vorlagen-Status entfernen: nur die vorlage:*-Tags abräumen,
  # die Notiz-KI selbst bleibt bestehen (kein Datenverlust).
  def destroy
    ki = KnowledgeItem.find_by!(uuid: params[:uuid])
    remaining = ki.tags.to_a.reject { |t| t.start_with?("vorlage:") }
    FileProxy.update(actor: current_actor, knowledge_item: ki, tags: remaining)
    redirect_to settings_document_templates_path, notice: t("settings.document_templates.removed", title: ki.title)
  end

  private

  def controller_resource_type
    "KnowledgeItem"
  end
end
