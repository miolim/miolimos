# #634 (Hans, 2026-06-12): Android-Share-Target der PWA. Das
# Web-App-Manifest (public/manifest.webmanifest) deklariert POST /share
# als share_target — geteilte URLs/Texte/Dateien aus dem Android-
# Teilen-Menü landen hier und werden zu Inbox-Einträgen.
#
# CSRF: der POST kommt vom Share-Sheet, nicht aus einem Rails-Formular —
# kein Token möglich. Auth bleibt: ohne Session geht es zum Login.
class SharesController < ApplicationController
  include InboxItemUploads

  skip_before_action :verify_authenticity_token, only: :create

  # Direktaufruf im Browser (GET /share) — einfach zur Inbox.
  def show
    redirect_to inbox_items_path
  end

  def create
    item =
      if (file = params[:file]).respond_to?(:original_filename)
        store_uploaded_file!(file)
      else
        # Viele Apps (z. B. YouTube) packen die URL in `text` statt `url`.
        url = params[:url].presence || extract_url(params[:text])
        if url
          kind = Inbox::Processors::YoutubeTranscribe.youtube_url?(url) ? "youtube_url" : "web_url"
          InboxItem.create!(creator: current_actor, source_kind: kind,
                            source_url: url, title: params[:title].presence)
        else
          content = [params[:title], params[:text]].map(&:presence).compact.join("\n\n")
          raise ActionController::BadRequest, "Share ohne Inhalt" if content.blank?
          InboxItem.create!(creator: current_actor, source_kind: "text",
                            raw_content: content, title: params[:title].presence)
        end
      end

    if item.source_url.present? && item.title.to_s.strip.blank? && item.payload["title"].to_s.strip.blank?
      FetchInboxTitleJob.perform_later(item.id)
    end
    redirect_to inbox_items_path(stack: "list:inbox_items,inboxitem:#{item.id}"),
                notice: "In die Inbox übernommen."
  end

  private

  def extract_url(text)
    text.to_s[%r{https?://\S+}]
  end

  def controller_resource_type
    "InboxItem"
  end

  def controller_action_to_capability
    "create"
  end
end
