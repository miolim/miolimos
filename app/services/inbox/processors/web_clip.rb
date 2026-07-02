require "net/http"
require "uri"
require "nokogiri"

module Inbox
  module Processors
    # Minimaler Web-Clipper: lädt die URL, extrahiert title und ein
    # simpel-aufgeräumtes Body-Text, legt KI als web_clip an. Ohne
    # readability-Bibliothek; reicht für die meisten Artikel-Pages.
    class WebClip < ProcessorBase
      def self.kind        = "web_clip"
      def self.label       = "Web-Page als KI clippen"
      def self.description = "Lädt die URL, extrahiert Title + Text-Inhalt, legt als web_clip-KI an."

      def self.applies?(item)
        item.source_kind == "web_url" &&
          !YoutubeTranscribe.youtube_url?(item.source_url)
      end

      def process!(item, actor:)
        url = item.source_url.to_s.strip
        raise "InboxItem hat keine source_url" if url.empty?

        html = fetch_html(url)
        meta   = extract_meta_tags(html)
        title  = (meta[:title].presence || extract_title(html).presence ||
                  item.title.presence || url)
        body   = extract_article(url, html)

        src = upsert_source(url, title, meta, actor: actor)

        ki = FileProxy.create(
          actor:      actor,
          title:      title,
          item_type:  :transcript,
          content:    body
        )
        if src
          ki.update!(bib_source_id: src.id)
          FileProxy.merge_frontmatter!(actor: actor, knowledge_item: ki,
                                        bib_source: src.slug)
        end
        record_result(item, knowledge_item: ki)
      end

      # Source als webpage anlegen, Slug aus URL-Hostname + sluggified
      # title. Idempotent über url/title-Kombo. Mit erweiterten Meta-
      # Daten (Author, Description, Site-Name, Published-Date) — siehe
      # #124.
      #
      # #201: Author bekommt zusätzlich eine source_creators-Row (als
      # Person-KI, weil <meta name=author> typischerweise einen
      # Personen-Namen liefert). Bei Mehrdeutigkeit lässt sich das KI
      # später händisch zur Organization umschwenken.
      def upsert_source(url, title, meta, actor:)
        slug = build_slug(url, title)
        return nil if slug.blank?
        s = Source.find_or_initialize_by(slug: slug)
        s.assign_attributes(
          csl_type:        "webpage",
          title:           title,
          publisher:       meta[:author].presence,
          container_title: meta[:site_name].presence,
          abstract:        meta[:description].presence,
          issued_string:   meta[:published].presence,
          issued_date:     parse_iso_date(meta[:published]),
          language:        meta[:language].presence,
          url:             url,
          accessed:        Date.current,
          creator:         actor
        )
        s.save!
        Inbox::SourceCreatorLink.link_person!(s, meta[:author], actor: actor)
        s
      rescue => e
        Rails.logger.warn("WebClip: Source-Upsert fehlgeschlagen: #{e.class} #{e.message}")
        nil
      end

      def build_slug(url, title)
        host = URI.parse(url).host.to_s.sub(/\Awww\./, "")
        title_slug = title.to_s.parameterize.first(40)
        return nil if host.blank? && title_slug.blank?
        [host.tr(".", "-"), title_slug].reject(&:blank?).join("-")
      end

      private

      def fetch_html(url, max_redirects: 5)
        uri = URI.parse(url)
        max_redirects.times do
          res = Net::HTTP.start(uri.host, uri.port,
                                use_ssl: uri.scheme == "https",
                                open_timeout: 5, read_timeout: 10) do |http|
            http.request(Net::HTTP::Get.new(uri, "User-Agent" => "miolimOS/1.0 (+webclip)"))
          end
          case res
          when Net::HTTPSuccess
            return res.body.to_s.force_encoding("UTF-8")
          when Net::HTTPRedirection
            uri = URI.parse(res["location"])
          else
            raise "HTTP #{res.code} für #{url}"
          end
        end
        raise "Zu viele Redirects für #{url}"
      end

      def extract_title(html)
        m = html.match(%r{<title[^>]*>(.+?)</title>}im)
        return "" unless m
        decode_entities(m[1].strip.gsub(/\s+/, " "))
      end

      # Sammelt die wichtigsten Meta-Tags aus dem HTML — OpenGraph
      # zuerst (am verlässlichsten), dann Standard-meta + JSON-LD-
      # Fallbacks. Reicht für 90 % der Artikel-Pages, ohne Readability-
      # Bibliothek. (#124)
      def extract_meta_tags(html)
        {
          title:       meta_value(html, %w[og:title twitter:title]),
          author:      meta_value(html, %w[author article:author og:author twitter:creator]),
          description: meta_value(html, %w[og:description description twitter:description]),
          site_name:   meta_value(html, %w[og:site_name application-name]),
          published:   meta_value(html, %w[article:published_time og:published_time
                                            citation_publication_date date dc.date pubdate]),
          language:    extract_lang_attr(html)
        }
      end

      # Schaut der Reihe nach in <meta name="…"> und <meta property="…">
      # nach den gegebenen Keys; liefert den ersten nicht-leeren content.
      def meta_value(html, keys)
        keys.each do |key|
          esc = Regexp.escape(key)
          m = html.match(%r{<meta\s+(?:name|property)=["']#{esc}["']\s+content=["']([^"']+)["']}im) ||
              html.match(%r{<meta\s+content=["']([^"']+)["']\s+(?:name|property)=["']#{esc}["']}im)
          return decode_entities(m[1].strip) if m && !m[1].strip.empty?
        end
        nil
      end

      def extract_lang_attr(html)
        m = html.match(%r{<html\s+[^>]*lang=["']([a-zA-Z-]+)["']}im)
        m && m[1].downcase
      end

      def parse_iso_date(s)
        return nil if s.blank?
        Date.parse(s.to_s) rescue nil
      end

      # #693 (Hans): Readability-lite via Nokogiri statt roher Tag-Strip.
      # Vorher landete die GANZE Seite (Navigation, Footer, Cookie-Banner,
      # Player-Bedienelemente) im Body. Jetzt: Boilerplate-Container
      # entfernen, den Hauptinhalt bevorzugen (<article> mit dem meisten
      # Text, sonst <main>, sonst <body>) und nur Inhalts-Blöcke (p/h/li/
      # blockquote) als Text ziehen. (Paywall bleibt unlösbar — bei
      # zahlungspflichtigen Artikeln kommt nur die öffentliche Vorschau.)
      def extract_body(html, base_url = nil)
        doc = Nokogiri::HTML(html)
        # NUR klare Boilerplate-Container entfernen. <header>/<figcaption>
        # bleiben drin — dort steht oft der Standfirst/Untertitel (Inhalt);
        # die Seiten-Chrome hält die <article>-Präferenz unten ohnehin raus.
        doc.css(
          "script, style, noscript, nav, footer, aside, form, svg, " \
          "button, iframe, [role=navigation], [role=banner], " \
          "[role=contentinfo], [aria-hidden=true]"
        ).remove
        # #693 (Hans): Social-/Teilen-Listen leaken sonst ans Artikelende
        # (z.B. „Facebook Messenger", „E-Mail"). Klassen-basiert raus (CSS
        # ohne i-Flag — Nokogiri kennt es nicht; Klassen sind lowercase).
        doc.css("[class*=share], [class*=Share], [class*=social], " \
                "[class*=Social], [class*=teilen], [data-ct-area*=sharing]").remove

        articles = doc.css("article")
        root = if articles.any?
                 articles.max_by { |a| a.text.to_s.length }
               else
                 doc.at_css("main") || doc.at_css("body") || doc
               end

        # #736 (Hans): Interview-Fragen stehen bei manchen Seiten (z.B.
        # FAZ) als block-eigenstaendige <strong>/<b> NEBEN den Antwort-
        # <p> — nicht in p/h/li/blockquote. Vorher fielen sie raus und das
        # Interview wurde zur fragenlosen Antwort-Wueste. Loesung: solche
        # standalone <strong>/<b> als Inhaltsbloecke mitnehmen — aber NUR,
        # wenn sie nicht in einem Block stecken (inline-Fett im Absatz waere
        # sonst doppelt). css() liefert die Knoten in Dokumentreihenfolge,
        # Frage und Antwort bleiben also korrekt verzahnt.
        inline_tags = %w[strong b]
        block_tags  = %w[p h1 h2 h3 h4 h5 h6 li blockquote]
        blocks = root.css("p, h1, h2, h3, h4, h5, h6, li, blockquote, strong, b").reject do |b|
          inline_tags.include?(b.name) &&
            b.ancestors.any? { |a| block_tags.include?(a.name) }
        end
        # #693 (Hans): Boilerplate-Zeilen filtern. #758: der Filter prüft den
        # REINEN Text des Blocks — die Markdown-Marker (`#`, `**`, `>`) würden
        # die Exakt-Vergleiche der Share-Labels sonst brechen.
        share_labels = ["facebook", "facebook messenger", "messenger", "twitter",
                        "x", "whatsapp", "telegram", "e-mail", "email", "teilen",
                        "drucken", "merken", "link kopieren", "kommentieren",
                        "pocket", "linkedin", "xing", "flipboard"]
        # #693 (Hans): Z+/Freebie-Schenk-Banner ist kein Artikelinhalt.
        gift_re = /schenken sie diesen z|diesen monat können sie noch|artikel verschenken|sie haben diesen z\+|jemandem ohne abo/i
        boilerplate = lambda do |plain|
          dl = plain.downcase
          plain.length < 2 ||
            share_labels.include?(dl) ||
            dl.match?(/\A(jetzt )?(teilen|drucken|merken)( auf)?:?\z/) ||
            plain.match?(gift_re)
        end

        # #758 (Hans, 2026-06-22): Auszeichnungen MITNEHMEN — jeden Inhalts-
        # block zu Markdown wandeln (Überschriften → #, Fett → **, Kursiv → *,
        # Listen → -, Zitate → >, Links → []()) statt nur `.text` zu ziehen.
        if blocks.any?
          blocks.filter_map { |node|
            next if boilerplate.call(node.text.to_s.strip.gsub(/\s+/, " "))
            block_to_markdown(node, base_url).strip.presence
          }.join("\n\n")
        else
          root.text.to_s.split("\n").map(&:strip).reject { |l| boilerplate.call(l) }.join("\n\n")
        end
      end

      # #758 (Hans, 2026-06-22): Einen Inhaltsblock-Knoten in eine Markdown-
      # Zeile wandeln. Überschriften/Listen/Zitate bekommen ihr Präfix, der
      # Rest (Absatz, standalone-Fett aus #736) übernimmt nur die Inline-
      # Auszeichnung.
      def block_to_markdown(node, base_url = nil)
        inner = inline_markdown(node, base_url).strip
        return "" if inner.empty?
        case node.name
        when /\Ah([1-6])\z/
          ("#" * Regexp.last_match(1).to_i) + " " + inner
        when "li"
          "- " + inner
        when "blockquote"
          inner.split("\n").map { |l| "> #{l}".rstrip }.join("\n")
        when "strong", "b"
          "**#{inner}**"
        else
          inner
        end
      end

      # Wandelt die Kind-Knoten eines Elements in Inline-Markdown. Fett/Kursiv/
      # Code/Links werden ausgezeichnet; führende/abschließende Leerzeichen
      # bleiben AUSSERHALB der Marker (sonst ungültiges Markdown, z.B. `** x **`).
      def inline_markdown(node, base_url = nil)
        node.children.map { |c| inline_node(c, base_url) }.join
      end

      def inline_node(node, base_url = nil)
        return node.text.gsub(/\s+/, " ") if node.text?
        return "" unless node.element?

        inner = inline_markdown(node, base_url)
        lead  = inner[/\A\s*/]
        trail = inner[/\s*\z/]
        core  = inner.strip

        case node.name
        when "strong", "b"
          core.empty? ? inner : "#{lead}**#{core}**#{trail}"
        when "em", "i"
          core.empty? ? inner : "#{lead}*#{core}*#{trail}"
        when "code"
          core.empty? ? inner : "#{lead}`#{core}`#{trail}"
        when "a"
          href = absolutize(node["href"].to_s.split("#").first, base_url) || node["href"].to_s
          (core.empty? || href.blank?) ? inner : "#{lead}[#{core}](#{href})#{trail}"
        when "br"
          " "
        else
          inner
        end
      end

      # #693 (Hans): Viele Artikel sind über mehrere HTML-Seiten verteilt
      # (Zeit.de: „Seite 1/6"). Ein anonymer/Freebie-Abruf der Artikel-URL
      # liefert dann nur Seite 1. Lösung: die „Auf einer Seite"-/Komplett-
      # ansicht-Version bevorzugen (eine Anfrage, ganzer Artikel); fehlt
      # die, den Pagination-Seiten (…/seite-N) folgen und die Bodies
      # zusammenfügen. Die Query der Ausgangs-URL (z.B. ?freebie=…) wird auf
      # die Folge-URLs übernommen, damit die Paywall auch dort offen bleibt.
      def extract_article(url, html)
        doc       = Nokogiri::HTML(html)
        base_body = extract_body(html, url)

        single = single_page_url(doc, url)
        if single
          begin
            full = extract_body(fetch_html(single), single)
            return full if full.length > base_body.length
          rescue => e
            Rails.logger.warn("WebClip: Komplettansicht #{single} fehlgeschlagen: #{e.class} #{e.message}")
          end
        end

        pages = pagination_urls(doc, url)
        if pages.any?
          bodies = [base_body]
          pages.each do |purl|
            begin
              bodies << extract_body(fetch_html(purl), purl)
            rescue => e
              Rails.logger.warn("WebClip: Subseite #{purl} fehlgeschlagen: #{e.class} #{e.message}")
            end
          end
          joined = bodies.reject(&:blank?).join("\n\n")
          return joined if joined.length > base_body.length
        end

        base_body
      end

      # „Auf einer Seite lesen"/Komplettansicht-Link: erster Treffer (href
      # enthält „komplettansicht" ODER Linktext „Auf einer Seite"), absolut
      # gemacht, Fragment gestreift, Query der Ausgangs-URL geerbt. Nil,
      # wenn es dieselbe Seite wäre.
      def single_page_url(doc, base_url)
        link = doc.css("a[href]").find do |a|
          a["href"].to_s.match?(/komplettansicht/i) ||
            a.text.to_s.strip.match?(/\Aauf einer seite\b/i)
        end
        return nil unless link
        target = absolutize(link["href"].to_s.split("#").first, base_url)
        return nil if target.blank? || same_page?(target, base_url)
        inherit_query(target, base_url)
      end

      # Pagination-Seiten (…/seite-N oder ?seite=/?page=N), dedupliziert in
      # Dokumentreihenfolge, ohne die aktuelle (erste) Seite.
      def pagination_urls(doc, base_url)
        seen = {}
        doc.css("a[href]").each do |a|
          href = absolutize(a["href"].to_s.split("#").first, base_url)
          next if href.blank?
          next unless href.match?(%r{/seite-\d+\b}i) || href.match?(/[?&](seite|page)=\d+\b/i)
          next if same_page?(href, base_url)
          seen[href] ||= inherit_query(href, base_url)
        end
        seen.values
      end

      def absolutize(href, base_url)
        return nil if href.blank?
        URI.join(base_url, href).to_s
      rescue StandardError
        nil
      end

      # Query (z.B. freebie-Token) der Ausgangs-URL übernehmen, falls die
      # Ziel-URL selbst keine hat.
      def inherit_query(target, base_url)
        q = (URI.parse(base_url).query rescue nil)
        return target if q.blank?
        u = URI.parse(target)
        u.query = q if u.query.blank?
        u.to_s
      rescue StandardError
        target
      end

      def same_page?(a, b)
        ua = URI.parse(a)
        ub = URI.parse(b)
        ua.host == ub.host && ua.path.to_s.chomp("/") == ub.path.to_s.chomp("/")
      rescue StandardError
        false
      end

      def decode_entities(s)
        s.gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">")
         .gsub("&quot;", '"').gsub("&#39;", "'").gsub("&nbsp;", " ")
         .gsub(/&#(\d+);/) { [Regexp.last_match(1).to_i].pack("U") }
      end
    end
  end
end
