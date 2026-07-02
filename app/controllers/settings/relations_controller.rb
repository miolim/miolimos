class Settings::RelationsController < Settings::BaseController
  # #239 Phase C: Uebersicht aller in Wikilinks vergebenen Beziehungs-
  # Labels. Free-Text-Labels in Relations werden aggregiert.
  # #239 Phase D: zusaetzlich CRUD fuer das kuratierte RelationType-
  # Vokabular. Labels und Types coexistieren — Types liefern die
  # Inverse-Bezeichnung (z.B. „loest aus" → „wird ausgeloest von").
  before_action :load_relation_type, only: [:update, :destroy]

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:relations")
  end

  def create
    rt = RelationType.new(permitted_attrs)
    if rt.save
      redirect_to settings_relations_path, notice: "Beziehungstyp angelegt."
    else
      redirect_to settings_relations_path,
                  alert: "Fehler: #{rt.errors.full_messages.join(', ')}"
    end
  end

  def update
    if @relation_type.update(permitted_attrs)
      redirect_to settings_relations_path, notice: "Beziehungstyp aktualisiert."
    else
      redirect_to settings_relations_path,
                  alert: "Fehler: #{@relation_type.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    @relation_type.destroy
    redirect_to settings_relations_path, notice: "Beziehungstyp geloescht."
  end

  private

  def load_relation_type
    @relation_type = RelationType.find(params[:id])
  end

  def permitted_attrs
    params.require(:relation_type).permit(:name, :inverse_name, :description, :ebene)
  end

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    case action_name
    when "create", "update", "destroy" then "update"
    else "read"
    end
  end
end
