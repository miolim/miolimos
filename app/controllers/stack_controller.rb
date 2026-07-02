# #434 Teil 2 (Hans, 2026-06-01): Generischer Resolver fuer den
# Verlauf-Drawer. Nimmt Stack-IDs (gemischte Typen) entgegen und liefert
# Anzeige-Labels — damit der Drawer auf JEDEM Stack echte Titel zeigt,
# nicht nur im Wissensbereich (dessen Resolver nur KI-UUIDs kennt).
class StackController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:resolve]

  # POST /stack/resolve  Body: ids[]=... (oder uuids[]=... fuer Kompat)
  def resolve
    ids = params[:ids].presence || params[:uuids]
    # #434 (Hans, 2026-06-01): icon-Helper rendert das SVG-Partial im
    # Lookup-Format. Der Drawer ruft mit Accept: application/json -> ohne
    # diesen Override suchte er shared/icons/*.json.erb (MissingTemplate ->
    # 500). Auf HTML zwingen; das finale render json: nutzt keine Templates.
    view_context.lookup_context.formats = [:html]
    items = StackHistoryResolver.resolve(ids).map do |it|
      # Server-gerendertes Lucide-SVG pro Eintrag (statt Emoji im Drawer) —
      # Single Source of Truth ueber den icon-Helper.
      it.merge(icon_svg: view_context.icon(ICON_FOR[it[:item_type]] || "file_text", size: "w-4 h-4"))
    end
    render json: { items: items }
  end

  private

  # item_type (StackHistoryResolver#kind_for) -> Lucide-Icon-Name
  # (app/views/shared/icons/*). Fallback: file_text.
  ICON_FOR = {
    "task"          => "tasks",
    "topic"         => "folder", "topic_list" => "folder",
    "topic_render"  => "folder", "topic_refs" => "folder",
    "list"          => "folder", "tag_list"   => "tag",
    "source"        => "quote",
    "awaiting"      => "clock",
    "communication" => "communications", "comment" => "communications",
    "reply"         => "communications",
    "person"        => "user", "organization" => "building",
    "ki_refs"       => "bookmark",
    "missing"       => "trash"
  }.freeze

  def controller_resource_type
    "Task"  # reiner Lese-Lookup; Cap am Task (wie tags#).
  end

  def controller_action_to_capability
    "read"
  end
end
