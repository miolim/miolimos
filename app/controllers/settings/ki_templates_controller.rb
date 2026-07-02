class Settings::KiTemplatesController < Settings::BaseController
  before_action :set_template, only: [:edit, :update, :destroy]

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:ki_templates")
  end

  def create
    @template = KiTemplate.new(template_params)
    if @template.save
      redirect_to settings_ki_templates_path, notice: "KI-Vorlage angelegt."
    else
      @templates = KiTemplate.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @templates = KiTemplate.order(:name)
    render :index
  end

  def update
    if @template.update(template_params)
      redirect_to settings_ki_templates_path, notice: "KI-Vorlage aktualisiert."
    else
      @templates = KiTemplate.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    redirect_to settings_ki_templates_path, notice: "KI-Vorlage geloescht."
  end

  private

  def set_template
    @template = KiTemplate.find(params[:id])
  end

  def template_params
    params.require(:ki_template).permit(:name, :item_type, :title, :body)
  end
end
