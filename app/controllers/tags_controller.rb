# #418 (Hans, 2026-05-30): Tag-Listen-Blades.
# Tags sind kein eigenes Model — `string[]` auf Task und KI. Diese
# Controller-Action liefert ein Blade-Partial mit allen Tasks und KIs,
# die den gegebenen Tag tragen.
class TagsController < ApplicationController
  include KnowledgeStackHelpers

  # #456 (Hans, 2026-06-02): /tags als vollwertige Blade-Stack-Seite (wie
  # /tasks, /topics) mit der Tag-Liste als Starter. Eigener Pfad =
  # eigener Stack-Verlauf (`tags.stack.history`) und eigener stack.last-
  # Schluessel statt geteiltem /dashboard.
  def index
    params[:stack] = "list:tags" if params[:stack].blank?
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # Listen-Blade fuer EINEN Tag — zeigt Tasks + KIs mit diesem Tag.
  def list_card
    @tag = params[:tag].to_s
    @tasks = Task.visible_to(current_actor).open.without_template_tasks
                 .where("tasks.tags && ARRAY[?]::varchar[]", [@tag])
                 .includes(:topics, :assignee)
                 .order(created_at: :desc)
                 .to_a
    # #387 Phase B (Hans, 2026-05-30): KIs aufnehmen, deren Highlight-
    # Anker den Tag tragen — nicht nur KIs mit dem Tag auf der KI selbst.
    direct_uuids = KnowledgeItem
                    .where("knowledge_items.tags && ARRAY[?]::varchar[]", [@tag])
                    .pluck(:uuid)
    anchor_uuids = KnowledgeItemAnchor
                    .where("tags && ARRAY[?]::varchar[]", [@tag])
                    .pluck(:knowledge_item_uuid)
    ki_uuids     = (direct_uuids + anchor_uuids).uniq
    @knowledge_items = KnowledgeItem.visible_to(current_actor).where(uuid: ki_uuids).order(updated_at: :desc).to_a
    render partial: "tags/list_blade", locals: { tag: @tag, tasks: @tasks, knowledge_items: @knowledge_items }
  end

  # #418 Iter 2 (Hans, 2026-05-30): Listen-Blade ueber ALLE vergebenen
  # Tags. Klick auf einen Tag dispatcht ein blade-link mit kind=tag_list,
  # was das item-Blade danach anhaengt.
  def tags_list_card
    task_tags   = Task.visible_to(current_actor).where("array_length(tags, 1) > 0")
                      .pluck(Arel.sql("DISTINCT unnest(tags)"))
    ki_tags     = KnowledgeItem.visible_to(current_actor).where("array_length(tags, 1) > 0")
                               .pluck(Arel.sql("DISTINCT unnest(tags)"))
    anchor_tags = KnowledgeItemAnchor.where("array_length(tags, 1) > 0")
                                     .pluck(Arel.sql("DISTINCT unnest(tags)"))
    all_tags    = (task_tags + ki_tags + anchor_tags).reject(&:blank?).uniq
    map         = helpers.tag_icons_map
    @with_icon  = all_tags.select { |t| map.key?(t) }.sort
    @without_icon = (all_tags - @with_icon).sort
    render partial: "tags/tags_list_blade",
           locals: { with_icon: @with_icon, without_icon: @without_icon }
  end

  # #428 Phase 4 (Hans, 2026-05-31): Farbe/Beschreibung eines Tags setzen.
  # Tag wird bei Bedarf normalisiert angelegt. Auto-Submit vom Inline-Editor
  # in der Tag-Liste; schlanke Antwort (head :ok), Chips uebernehmen die
  # Farbe beim naechsten Render aus der Registry.
  def update
    tag = Tag.ensure(params[:tag])
    head(:unprocessable_entity) and return unless tag

    attrs = {}
    if params.key?(:color)
      col = params[:color].to_s.strip
      attrs[:color] = (ApplicationHelper::TAG_PALETTE.include?(col) && col != "slate") ? col : nil
    end
    attrs[:description] = params[:description].to_s.strip.presence if params.key?(:description)
    tag.update(attrs) unless attrs.empty?

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.json { render json: { ok: true, color: tag.color, description: tag.description } }
      format.html { redirect_back fallback_location: tags_list_card_path }
    end
  end

  private

  def controller_resource_type
    "Task"  # Tags sind kein eigenes Model — wir hängen die Cap am Task.
  end

  def controller_action_to_capability
    action_name == "update" ? "update" : "read"
  end
end
