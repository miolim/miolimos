# #203 Phase E.7: Index-State des TasksController als Form-Object.
# Buendelt Group-Mode, Filter/Sort (via TaskQuery), Sections und
# Trash-Count an einer Stelle — der Controller bleibt eine Zuweisungs-
# Schicht.
#
#   state = TaskIndexState.new(params: params, actor: current_actor)
#   state.group_by      # :time oder :topic
#   state.tasks         # ActiveRecord::Relation
#   state.sections      # [[:inbox, [...]], [:today, [...]], ...]  (Time-Mode)
#   state.topic_sections # [[Topic|nil, [...]], ...]               (Topic-Mode)
#   state.show_done     # delegiert an TaskQuery
class TaskIndexState
  attr_reader :group_by, :query, :tasks, :sections, :topic_sections, :trash_count

  delegate :q, :tag, :priority, :assignee_id, :show_done, :sort, :dir, :kind, :task_status,
           to: :@query

  def initialize(params:, actor:)
    @actor    = actor
    @group_by = parse_group(params)
    @query    = TaskQuery.new(params, actor: actor)
    @tasks    = @query.relation
    if @group_by == :topic
      build_topic_sections!
    else
      build_time_sections!
    end
    @trash_count = Task.discarded.where(assignee_id: actor.id).count
  end

  private

  # #87: Standardisierte URL-Param-Form `?group=…&sort=…&dir=…&q=…`
  # ersetzt das alte `?by=topic`. Backward-compat: `by=topic` wird auf
  # `group=topic` gemappt, damit alte Bookmarks/Links nicht brechen.
  def parse_group(params)
    raw = (params[:group].presence || (params[:by] == "topic" ? "topic" : "time")).to_s
    raw == "topic" ? :topic : :time
  end

  # Klassische Wann-Gruppierung (Eingang/Heute/Demnächst/Später).
  def build_time_sections!
    by_commit = @tasks.group_by(&:commitment)
    @sections = [
      [:inbox, by_commit[nil]     || []],
      [:today, by_commit["today"] || []],
      [:soon,  by_commit["soon"]  || []],
      [:later, by_commit["later"] || []]
    ]
  end

  # Topic-Gruppierung. „Ohne Projekt" zuoberst, danach Topics in
  # alphabetischer Reihenfolge. Ein Task taucht unter dem ersten Topic
  # auf, das er hat — Mehrfach-Topics führen also nicht zu Duplikaten
  # in der Liste (saubere Sortierung > visuelle Vollständigkeit).
  def build_topic_sections!
    @topic_sections = []
    no_topic = []
    by_topic = Hash.new { |h, k| h[k] = [] }
    @tasks.each do |task|
      first = task.topics.first
      first ? by_topic[first] << task : no_topic << task
    end
    @topic_sections << [nil, no_topic] # nil = Ohne Projekt
    by_topic.keys.sort_by { |t| t.name.to_s.downcase }.each do |t|
      @topic_sections << [t, by_topic[t]]
    end
  end
end
