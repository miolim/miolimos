require "open3"
require "uri"
require "net/http"

# Holt einen sprechenden Titel für ein frisch angelegtes Inbox-Item.
# Quelle: yt-dlp-Metadaten bei YouTube-URLs, sonst HTTP-GET + <title>-Tag.
# Schreibt das Ergebnis in payload["title"], was display_title automatisch
# anzeigt. Idempotent — überschreibt einen bestehenden payload["title"]
# nur, wenn er offensichtlich nichts taugt (leer oder nur Whitespace).
#
# Bewusst wenig Fehlerbehandlung: schlägt der Fetch fehl, bleibt das
# Item halt mit URL-Titel — kein Drama.
class FetchInboxTitleJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  USER_AGENT = "miolimOS/1.0 (+inbox-title-fetcher)"
  HTTP_TIMEOUT = 8

  def perform(inbox_item_id)
    item = InboxItem.find_by(id: inbox_item_id)
    return unless item
    return if item.payload["title"].to_s.strip.present?
    return if item.source_url.blank?

    title = if Inbox::Processors::YoutubeTranscribe.youtube_url?(item.source_url)
              fetch_youtube_title(item.source_url)
            else
              fetch_html_title(item.source_url)
            end

    return if title.blank?
    item.update!(payload: item.payload.merge("title" => title.strip))

    # #618 v4: Listenzeile live ersetzen — offene Inbox-Blades zeigen den
    # frischen Titel ohne Neuladen. Zielgruppe ist der Ersteller (sein
    # Stream); ist die Zeile gerade nicht im DOM (anderer Reiter), läuft
    # das Replace ins Leere — harmlos. Rescue NUR um den Broadcast —
    # ein perform-weites rescue hatte hier schon mal einen echten Bug
    # (YT_BIN) jahrelang verschluckt.
    begin
      Turbo::StreamsChannel.broadcast_replace_to(
        "inbox_items_user_#{item.creator_id}",
        target:  "inbox_row_#{item.id}",
        partial: "inbox_items/row",
        locals:  { item: item }
      )
    rescue => e
      Rails.logger.warn("FetchInboxTitleJob: Broadcast fehlgeschlagen: #{e.class} #{e.message}")
    end
  end

  private

  def fetch_youtube_title(url)
    # #618 v3: Konstante heißt Inbox::Yt::YtDlp::BIN (nicht YT_BIN am
    # Processor) — der alte Tippfehler wurde vom rescue still geschluckt,
    # YouTube-Titel kamen deshalb nie an.
    yt = Inbox::Yt::YtDlp::BIN
    out, _err, status = Open3.capture3(yt, "--no-warnings", "--no-playlist",
                                        "--skip-download",
                                        "--print", "%(title)s",
                                        url)
    return nil unless status.success?
    out.lines.first&.strip
  rescue => e
    Rails.logger.warn("FetchInboxTitleJob: yt-dlp failed: #{e.class} #{e.message}")
    nil
  end

  def fetch_html_title(url)
    uri = URI.parse(url)
    return nil unless %w[http https].include?(uri.scheme)

    response = Net::HTTP.start(uri.host, uri.port,
                                use_ssl: uri.scheme == "https",
                                open_timeout: HTTP_TIMEOUT,
                                read_timeout: HTTP_TIMEOUT) do |http|
      req = Net::HTTP::Get.new(uri.request_uri,
                                "User-Agent" => USER_AGENT,
                                "Accept" => "text/html,application/xhtml+xml")
      http.request(req)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    # Encoding aus Content-Type-Header oder einfach UTF-8 forcieren —
    # genaue Detection wäre Overkill für reine Title-Extraktion.
    body = response.body.to_s.force_encoding("UTF-8").scrub
    if (m = body.match(%r{<title[^>]*>(.*?)</title>}im))
      decode_html_entities(m[1].strip).gsub(/\s+/, " ")
    end
  rescue => e
    Rails.logger.warn("FetchInboxTitleJob: HTTP failed for #{url}: #{e.class} #{e.message}")
    nil
  end

  # Mini-Decoder für die häufigsten HTML-Entities. Reicht für Titel,
  # spart eine Dependency.
  def decode_html_entities(s)
    s.gsub("&amp;", "&")
     .gsub("&lt;", "<")
     .gsub("&gt;", ">")
     .gsub("&quot;", '"')
     .gsub("&#39;", "'")
     .gsub("&apos;", "'")
     .gsub("&nbsp;", " ")
     .gsub(/&#(\d+);/) { $1.to_i.chr(Encoding::UTF_8) rescue $~[0] }
  end
end
