# Filter-/Sortier-Logik für die Tasks-Index-Liste. Aus dem
# TasksController herausgezogen (#127), damit die Logik isoliert
# getestet werden kann und die Controller-Action wieder lesbar wird.
#
# Eingabe: Rails-Params + aktueller Actor. Liefert eine ActiveRecord-
# Relation sowie die normalisierten Filter-Werte für die Anzeige
# (aktive Chips, Reset-Link etc.) im View.
class TaskQuery
  COMMITMENT_ORDER = "CASE WHEN tasks.commitment IS NULL THEN 0 " \
                     "WHEN tasks.commitment = 0 THEN 1 "         \
                     "WHEN tasks.commitment = 1 THEN 2 "         \
                     "WHEN tasks.commitment = 2 THEN 3 ELSE 4 END".freeze

  # Erlaubte Sort-Keys + Default-Richtung. `manual` heißt: zurück zur
  # gewohnten Commitment-Section-Ordnung (Eingang/Heute/Demnächst/Später),
  # innerhalb der Sektion nach Priorität & Fälligkeit (#87).
  # #409 (Hans, 2026-05-30): `created_at` als Sort-Key + neuer Default.
  # Hans erwartet ohne explizite Auswahl die juengsten Aufgaben oben.
  SORT_KEYS = {
    "created_at" => :desc,
    "manual"     => :desc,
    "updated_at" => :desc,
    "title"      => :asc,
    "priority"   => :desc,
    "due_date"   => :asc
  }.freeze
  DEFAULT_SORT = "created_at"

  attr_reader :q, :tag, :priority, :assignee_id, :show_done, :sort, :dir, :kind, :task_status

  def initialize(params, actor:)
    @actor       = actor
    @q           = params[:q].to_s.strip.presence
    @tag         = params[:tag].to_s.strip.presence
    @priority    = params[:priority].to_s.strip.presence
    @assignee_id = params[:assignee_id].to_s.strip.presence
    # #572: Alle | Aufgaben | Meilensteine.
    @kind        = %w[tasks milestones].include?(params[:kind].to_s) ? params[:kind].to_s : nil
    @show_done   = ActiveModel::Type::Boolean.new.cast(params[:show_done])
    # #665: tri-state Status-Toggle (open|done|all) wie im Topic-Tab.
    # Hat Vorrang vor show_done; ohne Param greift weiter show_done.
    @task_status = %w[open done all].include?(params[:task_status].to_s) ? params[:task_status].to_s : nil
    @sort        = SORT_KEYS.key?(params[:sort].to_s) ? params[:sort].to_s : DEFAULT_SORT
    @dir         = %w[asc desc].include?(params[:dir].to_s) ? params[:dir].to_s : SORT_KEYS[@sort].to_s
  end

  def relation
    # #602 S1: Basis ist der Sichtbarkeits-Scope des Actors.
    scope = Task.visible_to(@actor)
      .includes(:topics, :task_topics, :assignee, :mentioned_kis, :subtasks, :predecessors)
      .where(parent_id: nil)
      .without_template_tasks
    scope = apply_assignee(scope)
    scope = apply_status(scope)
    scope = scope.where("tasks.tags && ARRAY[?]::varchar[]", [@tag]) if @tag
    scope = scope.where(tasks: { priority: @priority }) if @priority && Task.priorities.key?(@priority)
    # #572: Meilenstein-Filter (Alle = kein Filter).
    scope = scope.where(tasks: { client_milestone: @kind == "milestones" }) if @kind
    scope = apply_q(scope)
    apply_order(scope)
  end

  private

  # Sort-Anwendung: bei „manual" die bestehende Commitment-Section-Order;
  # andere Sort-Keys überschreiben sie durch eine einfache Spalten-Sortierung.
  # Hans-Wunsch (#87): manuelle Sortierung darf nicht „verloren gehen",
  # wenn der User vorübergehend nach z.B. updated_at sortiert. Da wir den
  # Sort-Key auswerten und nicht in die DB schreiben, ist „Manuell"
  # einfach das Default-Verhalten, das jederzeit wiederherstellbar ist.
  def apply_order(scope)
    direction = @dir.to_sym
    case @sort
    when "title"      then scope.order(Arel.sql("LOWER(tasks.title) #{direction}"))
    when "priority"   then scope.order(priority: direction, due_date: :asc)
    when "due_date"   then scope.order(Arel.sql("tasks.due_date #{direction} NULLS LAST"))
    when "updated_at" then scope.order(updated_at: direction)
    when "created_at" then scope.order(created_at: direction)
    else                   scope.order(Arel.sql(COMMITMENT_ORDER)).order(priority: :desc, due_date: :asc)
    end
  end

  # Default: aktueller Actor + unzugewiesene. `assignee_id=all` hebt das auf,
  # explizite ID filtert auf genau einen Actor. Spalte ist `tasks.assignee_id`
  # — qualifizieren, weil includes(:subtasks) zur self-join-Ambiguität führen
  # kann (subtasks ist eine Task → eigene assignee_id-Spalte).
  # #665: Status-Toggle (open|done|all) vor Fallback show_done.
  def apply_status(scope)
    case @task_status
    when "all"  then scope.where(status: [:open, :done])
    when "done" then scope.where(status: :done)
    when "open" then scope.open
    else             @show_done ? scope.where(status: [:open, :done]) : scope.open
    end
  end

  def apply_assignee(scope)
    case @assignee_id
    when "all"    then scope
    when "others" then scope.where.not("tasks.assignee_id = ? OR tasks.assignee_id IS NULL", @actor.id)
    when nil      then scope.where("tasks.assignee_id = ? OR tasks.assignee_id IS NULL", @actor.id)
    else               scope.where(tasks: { assignee_id: @assignee_id })
    end
  end

  # `?q=#101` oder `?q=101` matcht den Primary Key — Komfort, um eine
  # Aufgabe anhand der angezeigten Nummer schnell zu finden. Sonst
  # Substring auf Title + Description.
  def apply_q(scope)
    return scope unless @q
    if (m = @q.match(/\A#?(\d+)\z/))
      scope.where(tasks: { id: m[1].to_i })
    else
      like = "%#{@q.downcase}%"
      scope.where("LOWER(tasks.title) LIKE :q OR LOWER(COALESCE(tasks.description, '')) LIKE :q",
                  q: like)
    end
  end
end
