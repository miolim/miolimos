# Gemeinsames Verhalten für die drei "Topic-Chip an Entity"-Controller:
# TaskTopicsController, AwaitingTopicsController, CommunicationTopicsController.
#
# Jeder Sub-Controller konfiguriert:
#   nested_topic_config parent_class: Task, join_class: TaskTopic,
#                       id_param: :task_id, with_position: true
#
# und implementiert optional `on_success(parent)` für die individuelle
# Antwort-Logik (Turbo-Stream-Partials je nach Parent-Typ).
module NestedTopicAssignment
  extend ActiveSupport::Concern

  included do
    class_attribute :nested_topic_options, default: {}
  end

  class_methods do
    # Erwartete Keys:
    #   parent_class:   Task / Awaiting / Communication
    #   join_class:     TaskTopic / AwaitingTopic / CommunicationTopic
    #   id_param:       :task_id / :awaiting_id / :communication_id
    #   with_position:  true für TaskTopic (andere haben kein position-Feld)
    def nested_topic_config(**options)
      self.nested_topic_options = options
    end
  end

  def create
    parent = find_parent
    topic  = resolve_topic_from_params

    attrs = { parent_key => parent, topic: topic }
    if nested_topic_options[:with_position]
      link = join_class.find_or_initialize_by(attrs)
      link.position = params[:position].presence&.to_i ||
                      ((topic.task_topics.maximum(:position) || 0) + 1)
      link.save!
    else
      join_class.find_or_create_by!(attrs)
    end

    on_success(parent)
  end

  # Picker schickt entweder topic_id (existierendes Thema verlinken)
  # oder create_with ("Foo Bar") für Quick-Create + Verlinken in einer
  # Transaktion. Slug wird via parameterize abgeleitet, Name = Eingabe.
  # topic_id darf Slug oder numerische ID sein — wir probieren erst Slug.
  def resolve_topic_from_params
    if (text = params[:create_with].to_s.strip).present?
      slug = text.parameterize
      Topic.find_by(slug: slug) || Topic.create!(
        slug: slug, name: text, creator: current_actor,
        status: :active, template: false
      )
    else
      raw = params.require(:topic_id)
      Topic.find_by(slug: raw) || Topic.find(raw)
    end
  end

  def destroy
    parent = find_parent
    # Nested-Route-Default :id enthält bei Topic den Slug → Fallback.
    @unlinked_topic = Topic.find_by(slug: params[:id]) || Topic.find(params[:id])
    join_class.find_by(parent_key => parent, topic: @unlinked_topic)&.destroy
    on_success(parent)
  end

  private

  def find_parent
    nested_topic_options[:parent_class].find(params[nested_topic_options[:id_param]])
  end

  def join_class
    nested_topic_options[:join_class]
  end

  # Der Parent-FK-Name im Join-Model, z.B. :task für TaskTopic.
  def parent_key
    nested_topic_options[:parent_class].model_name.element.to_sym
  end

  # Sub-Controller überschreiben das, um turbo_stream vs. redirect zu wählen.
  def on_success(parent)
    redirect_back fallback_location: polymorphic_path(parent)
  end

  # Standard-Capability-Mapping: alles ist "update" auf den Parent-Typ.
  def controller_resource_type
    nested_topic_options[:parent_class].model_name.name
  end

  def controller_action_to_capability
    "update"
  end
end
