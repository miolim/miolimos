# #1321 (Hans, 2026-08-07): Die Suchlogik selbst liegt in SearchQuery —
# hier bleiben nur die drei Einstiege:
#
#   index      — das Schnell-Dropdown in der Topbar (Turbo-Frame, je Sektion
#                die ersten DROPDOWN_LIMIT Zeilen, ohne Zählung: die Aktion
#                feuert je Tastendruck, 11 COUNT-Queries wären dort Verschwendung)
#   list_card  — die Ergebnis-Card als Stack-Blade (Sektionsköpfe mit echter
#                Trefferzahl, Inhalt eingeklappt und lazy)
#   section    — die Zeilen EINER Sektion, nachgeladen beim Ausklappen und
#                beim „weitere anzeigen"
#
# payload (?p=) ist base64url(suchbegriff) — analog pdfcard (#1025). Der
# Suchbegriff steckt damit in der Stack-Id (`list:search:<payload>`) und
# übersteht Reload und Stack-Restore, ohne dass Komma oder Leerzeichen den
# kommaseparierten ?stack=-Param sprengen.
class SearchController < ApplicationController
  DROPDOWN_LIMIT = 8
  MAX_LIMIT      = 500

  def index
    @search  = SearchQuery.new(params[:q], actor: current_actor)
    @payload = SearchQuery.encode_payload(@search.query)

    respond_to do |format|
      format.html
      format.turbo_stream { render :index }
    end
  end

  def list_card
    search = search_from_payload
    render partial: "search/list_blade_card",
           locals: { payload: params[:p].to_s, search: search },
           layout: false
  end

  def section
    search  = search_from_payload
    section = params[:section].to_s.to_sym
    raise ActiveRecord::RecordNotFound unless SearchQuery::SECTIONS.include?(section)

    render partial: "search/section_rows",
           locals: { search: search, payload: params[:p].to_s, section: section,
                     limit: requested_limit },
           layout: false
  end

  private

  def search_from_payload
    SearchQuery.new(SearchQuery.decode_payload(params[:p]), actor: current_actor)
  rescue SearchQuery::BadPayload
    raise ActiveRecord::RecordNotFound
  end

  def requested_limit
    given = params[:limit].to_i
    given = SearchQuery::PAGE_SIZE if given <= 0
    given.clamp(SearchQuery::PAGE_SIZE, MAX_LIMIT)
  end

  def controller_resource_type
    # Suche ist ein Meta-Zugriff, der tieferen AccessGate pro Resource-Ebene
    # bewusst umgeht (für V1). Wir prüfen hier gegen Task (read) als weichen
    # Default; die einzelnen Sammlungen filtert SearchQuery über ihre
    # visible_to-Scopes (#602 S1).
    "Task"
  end
end
