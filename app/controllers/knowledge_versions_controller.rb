# Versionshistorie für KIs. Aus KnowledgeItemsController (#127)
# ausgelagert. URLs bleiben stabil:
#
#   GET  /knowledge_items/:uuid/history         → index
#   GET  /knowledge_items/:uuid/version?sha=…   → show
#   POST /knowledge_items/:uuid/restore_version → restore
#
# Die History selbst liest `KiHistory` aus dem Daten-Repo (git log).
class KnowledgeVersionsController < ApplicationController
  before_action :set_item

  def index
    @commits = KiHistory.for_path(@item.file_path, limit: 50)
    render partial: "knowledge_items/history_panel",
      locals: { item: @item, commits: @commits }, layout: false
  end

  # Inhalt einer früheren Version anzeigen (für Diff/Restore-Vorschau).
  def show
    sha = params.require(:sha)
    raw = KiHistory.show(@item.file_path, sha)
    fm, body = MarkdownFrontmatter.parse(raw)
    render partial: "knowledge_items/version_preview",
      locals: { item: @item, sha: sha, body: body, frontmatter: fm }, layout: false
  end

  # Eine alte Version wiederherstellen — schreibt den damaligen Body
  # über FileProxy.update zurück (= neuer Commit, History bleibt erhalten).
  def restore
    sha = params.require(:sha)
    raw = KiHistory.show(@item.file_path, sha)
    raise "Inhalt der Version leer oder Datei umbenannt — Restore manuell" if raw.blank?
    fm, body = MarkdownFrontmatter.parse(raw)
    FileProxy.update(actor: current_actor, knowledge_item: @item,
                     content: body,
                     title:   fm["title"].presence || @item.title)
    redirect_to knowledge_item_path(@item.uuid),
      notice: "Version #{sha[0,8]} wiederhergestellt."
  rescue => e
    redirect_to knowledge_item_path(@item.uuid), alert: "Restore fehlgeschlagen: #{e.message}"
  end

  private

  def set_item
    @item = KnowledgeItem.find(params[:uuid])
  end

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    action_name == "restore" ? "update" : "read"
  end
end
