class PromptTemplatesController < ApplicationController
  before_action :set_template, only: [:show, :edit, :update, :destroy]

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:prompt_templates")
  end

  # #613 St.2: Einzelfenster abgelöst — als Blade im Einstellungs-Stack.
  def show
    redirect_to settings_path(stack: "list:settings,settings:prompt_templates,settingssub:prompt_templates:#{@template.slug}")
  end

  def new
    redirect_to settings_path(stack: "list:settings,settings:prompt_templates,settingssub:prompt_templates:new")
  end

  def create
    @template = PromptTemplate.new(template_params.merge(creator: current_actor))
    if @template.save
      redirect_to settings_path(stack: "list:settings,settings:prompt_templates,settingssub:prompt_templates:#{@template.slug}"), notice: "Vorlage angelegt."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    redirect_to settings_path(stack: "list:settings,settings:prompt_templates,settingssub:prompt_templates:#{@template.slug}:edit")
  end

  def update
    if @template.update(template_params)
      redirect_to settings_path(stack: "list:settings,settings:prompt_templates,settingssub:prompt_templates:#{@template.slug}"), notice: "Gespeichert."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy!
    redirect_to prompt_templates_path, notice: "Vorlage gelöscht."
  end

  private

  def set_template
    @template = PromptTemplate.find_by!(slug: params[:slug])
  end

  def template_params
    p = params.require(:prompt_template).permit(:name, :slug, :description, :prompt_text, :default_model, :output_format)
    p[:slug] = (p[:slug].presence || p[:name]).to_s.parameterize
    p
  end

  def controller_resource_type
    "PromptTemplate"
  end
end
