# #564: Live-Broadcasts der Antworten — aus knowledge_item.rb extrahiert
# (reiner Code-Move von #232/#473). Bewusst synchron (kein broadcast_later):
# die Renders sind klein und die Reihenfolge bleibt deterministisch.
class KnowledgeItem < ApplicationRecord
  module ReplyBroadcasts
    extend ActiveSupport::Concern

    included do
      # #232 Phase 1 (B): Live-Updates fuer Antworten. Greift sowohl bei
      # Hans' Web-Replies als auch bei API-Replies, weil es am Modell-Commit
      # haengt. Entwuerfe (published_at nil) broadcasten NICHT — sie sind
      # nur fuer den Autor sichtbar.
      after_create_commit  :broadcast_reply_live,         if: :reply?
      after_update_commit  :broadcast_reply_live,         if: :reply?
      after_destroy_commit :broadcast_reply_live_destroy, if: :reply?
    end

    private

    # #232 (Hans, 2026-06-01): Live-Updates fuer Antworten OHNE Full-Page-
    # Morph — gezieltes Frame-Reload. Der Broadcast ersetzt NUR den Replies-
    # Listen-turbo-frame durch einen leeren src-Frame; jede offene Session
    # holt das Listen-Fragment per GET nach und rendert es mit IHREM
    # current_actor — viewer-korrekt (editable?, eigene Drafts, Reihenfolge).
    # Reload statt Append => idempotent: kein Duplikat, kein Autor-Skip noetig.
    def broadcast_reply_live
      return if published_at.nil?
      broadcast_reply_frame_reload
    end

    def broadcast_reply_live_destroy
      broadcast_reply_frame_reload
    end

    def broadcast_reply_frame_reload
      target = parent
      return unless target
      helpers = Rails.application.routes.url_helpers
      case parent_type
      when "Task"
        frame_id = "task_replies_list_frame_#{target.id}"
        src      = helpers.task_replies_path(target)
        count_id = "task_replies_count_#{target.id}"
        fk       = { parent_type: "Task", parent_id_int: target.id }
      when "KnowledgeItem"
        frame_id = "knowledge_replies_list_frame_#{target.uuid}"
        src      = helpers.knowledge_item_replies_path(target.uuid)
        count_id = "knowledge_replies_count_#{target.uuid}"
        fk       = { parent_type: "KnowledgeItem", parent_uuid: target.uuid }
      else
        return
      end
      # 1) Listen-Frame zum viewer-eigenen Reload anstossen.
      #    #473 (Hans, 2026-06-02): targets (CSS, querySelectorAll) statt
      #    target (getElementById, nur 1. Treffer) — dieselbe Aufgabe kann
      #    MEHRFACH im Stack offen sein. targets trifft alle Instanzen.
      broadcast_replace_to target, targets: "##{frame_id}",
        partial: "shared/replies_lazy_frame", locals: { frame_id: frame_id, src: src }
      # 2) Count gezielt aktualisieren (veroeffentlichte Anzahl, viewer-agnostisch).
      count = KnowledgeItem.published_replies.where(fk).count
      broadcast_update_to target, targets: "##{count_id}", html: (count.positive? ? "· #{count}" : "")
    end
  end
end
