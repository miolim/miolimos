class SearchController < ApplicationController
  def index
    q = params[:q].to_s.strip
    @q = q
    if q.length < 2
      @tasks = @contacts = @communications = @knowledge_items = @replies = []
      @ki_snippets = @task_snippets = @reply_snippets = {}
      @reply_parents = {}
    else
      # Postgres FTS: websearch_to_tsquery erlaubt natürliche Eingaben
      # ("foo bar", "phrase mit anführungszeichen", -ausschluss). Ranking
      # via ts_rank_cd; Snippet via ts_headline.
      tsq = ActiveRecord::Base.sanitize_sql_array(["websearch_to_tsquery('german', ?)", q])

      # Tasks: Volltext über title + description.
      # #602 S1: jede Treffer-Sammlung läuft durch den Sichtbarkeits-Scope.
      @tasks = Task.visible_to(current_actor).where("search_vector @@ #{tsq}")
                   .order(Arel.sql("ts_rank_cd(search_vector, #{tsq}) DESC"))
                   .limit(8)
                   .to_a
      # #481 (Hans, 2026-06-03): „#<nr>" findet die Aufgabe direkt über ihre
      # Nummer (z.B. #477) und stellt sie vorne ein — nicht nur Textfeld-
      # Treffer. Optionaler Space nach dem #.
      if (m = q.match(/\A#\s*(\d+)\z/)) && (direct = Task.visible_to(current_actor).find_by(id: m[1].to_i))
        @tasks = ([direct] + @tasks.reject { |t| t.id == direct.id }).first(8)
      end
      @task_snippets = headline_map(@tasks, q,
        sql: "ts_headline('german', coalesce(description, title), #{tsq}, 'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=20, MinWords=5')"
      )

      # Personen/Orgs: KIs via FTS + zusätzlich contact_points (Email
      # etc.) per Substring.
      like     = "%#{q.downcase}%"
      cp_uuids = ContactPoint.where("LOWER(value) LIKE ?", like).pluck(:knowledge_item_uuid)
      @contacts = KnowledgeItem.visible_to(current_actor).persons_and_orgs.where(
        "search_vector @@ #{tsq} OR uuid IN (:cp_uuids)",
        cp_uuids: cp_uuids
      ).limit(8)

      # Andere KIs: Volltext über title + aliases + tags + body.
      # Replies separat behandeln (kein Title, link auf Parent + anchor).
      reply_enum = KnowledgeItem.item_types[:reply]
      @knowledge_items = KnowledgeItem.visible_to(current_actor)
        .where.not(item_type: [:person, :organization, :reply])
        .where("search_vector @@ #{tsq}")
        .order(Arel.sql("ts_rank_cd(search_vector, #{tsq}) DESC"))
        .limit(8)
      @ki_snippets = headline_map(@knowledge_items, q,
        sql: "ts_headline('german', coalesce(body, ''), #{tsq}, 'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=25, MinWords=5')"
      )

      # #395 (Hans, 2026-05-28): Antworten (Reply-KIs) als eigene
      # Sektion. Nur published — Drafts bleiben privat. Link zeigt
      # auf Parent + #reply_<uuid>-Anker.
      @replies = KnowledgeItem.visible_to(current_actor)
        .where(item_type: reply_enum)
        .where.not(published_at: nil)
        .where("search_vector @@ #{tsq}")
        .order(Arel.sql("ts_rank_cd(search_vector, #{tsq}) DESC"))
        .limit(8)
        .to_a
      @reply_snippets = headline_map(@replies, q,
        sql: "ts_headline('german', coalesce(body, ''), #{tsq}, 'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=25, MinWords=5')"
      )
      # Parent-Records vor-laden (Task oder KI).
      task_parent_ids = @replies.select { |r| r.parent_type == "Task" }.map(&:parent_id_int)
      ki_parent_uuids = @replies.select { |r| r.parent_type == "KnowledgeItem" }.map(&:parent_uuid)
      @reply_parents = {}
      Task.visible_to(current_actor).where(id: task_parent_ids).each { |t| @reply_parents[[ "Task", t.id ]] = t } if task_parent_ids.any?
      KnowledgeItem.visible_to(current_actor).where(uuid: ki_parent_uuids).each { |k| @reply_parents[[ "KnowledgeItem", k.uuid ]] = k } if ki_parent_uuids.any?

      @communications = Communication.visible_to(current_actor).where("LOWER(COALESCE(subject, '')) LIKE ?", like).limit(8)
    end

    respond_to do |format|
      format.html
      format.turbo_stream { render :index }
    end
  end

  private

  # Stellt für jede gefundene Zeile einen HTML-Snippet bereit (id => html).
  # ts_headline ist relativ teuer, deshalb in einer einzigen Query je Sammlung
  # statt pro Ergebnis.
  def headline_map(records, _query, sql:)
    return {} if records.empty?
    klass = records.first.class
    pk    = klass.primary_key
    ids   = records.map(&pk.to_sym)
    rows  = klass.where(pk => ids).pluck(pk, Arel.sql(sql))
    rows.to_h
  end

  def controller_resource_type
    # Suche ist ein Meta-Zugriff, der tieferen AccessGate pro Resource-Ebene
    # bewusst umgeht (für V1). Wir prüfen hier gegen Task (read) als weichen
    # Default; feingranulare Filterung folgt, wenn AccessGate per-Record wird.
    "Task"
  end
end
