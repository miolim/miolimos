# #631 v2: Verlauf-Logik für das selbstladende Blade + den
# „Mehr laden"-Endpoint — Query, Bulk-Preload und Typ-Bestimmung an
# einer Stelle (das Blade rendert auch auf fremden Stack-Seiten, darum
# Helper statt Controller-Assigns).
module HistoryHelper
  HISTORY_PAGE_SIZE = 100

  # Jüngste Views des aktuellen Actors, eine Zeile pro Entität
  # (DISTINCT ON, jüngster View gewinnt). before: Unix-Timestamp (Float)
  # für die Blätter-Seiten.
  def history_recent_views(before: nil, limit: HISTORY_PAGE_SIZE)
    scope = ActorView.for_actor(current_actor).recent
    scope = scope.where("viewed_at < ?", Time.zone.at(before.to_f)) if before.present?
    sql_inner = <<~SQL
      SELECT DISTINCT ON (viewable_type, viewable_id) *
      FROM (#{scope.to_sql}) AS sub
      ORDER BY viewable_type, viewable_id, viewed_at DESC
    SQL
    ActorView.from(Arel.sql("(#{sql_inner}) AS actor_views"))
             .order(viewed_at: :desc)
             .limit(limit)
             .to_a
  end

  # Polymorphes Bulk-Loading — { [type, id_string] => record }.
  def history_preload_viewables(views)
    result = {}
    views.group_by(&:viewable_type).each do |type, vs|
      klass = type.safe_constantize
      next unless klass
      pk  = klass.primary_key
      ids = vs.map(&:viewable_id).uniq
      klass.where(pk => ids).each { |r| result[[type, r.id.to_s]] = r }
    end
    result
  end

  # #632: Personen-/Organisations-KIs als eigener Filter-Typ.
  def history_effective_type(view, rec)
    if view.viewable_type == "KnowledgeItem" && rec.respond_to?(:item_type) &&
       %w[person organization].include?(rec.item_type.to_s)
      "Person"
    else
      view.viewable_type
    end
  end
end
