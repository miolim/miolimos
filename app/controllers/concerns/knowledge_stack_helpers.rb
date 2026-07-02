module KnowledgeStackHelpers
  extend ActiveSupport::Concern

  private

  # Initialer Stack aus URL.
  #
  # Versteht zwei Param-Varianten:
  #   ?stack=u1,task:42,topic:foo,src:bar  →  gemischter Cross-Entity-Stack
  #   ?selected=<uuid>                      →  Legacy-Single-KI
  #
  # Rueckgabe: Array<BladeStackLoader::Item>. Reihenfolge entspricht dem
  # URL-Param, fehlende IDs werden ausgelassen.
  def build_initial_stack
    if params[:stack].present?
      BladeStackLoader.parse(params[:stack])
    elsif params[:selected].present?
      ki = KnowledgeItem.visible_to(current_actor).find_by(uuid: params[:selected])
      ki ? [BladeStackLoader::Item.new(kind: :ki, id: ki.uuid, record: ki)] : []
    else
      []
    end
  end

  # Body-HTML nur fuer die KI-Items im Stack laden (alle anderen Blade-
  # Types tragen ihren Render-Content im Card-Partial selbst).
  def bodies_for_initial_stack(items)
    items.select { |i| i.kind == :ki }
         .to_h { |i| [i.record.uuid, load_body_html(i.record)] }
  end

  # Liest die Markdown-Datei und rendert HTML samt Wikilinks/Block-
  # Anchors. Bei Transcript-KIs mit Binär-Attachment (PDF etc.) wird
  # stattdessen ein eingebetteter Viewer + Download-Link geliefert.
  # Bei fehlender Datei: Hinweis-Snippet, kein Crash.
  def load_body_html(item)
    # #705 (Hans): HTML-Render-Modus zeigt den Body als sandboxed iframe
    # (in der View) — hier nichts als Markdown vorrendern.
    return nil if item.respond_to?(:render_html?) && item.render_html?
    return document_embed_html(item) if binary_attachment?(item)
    body = FileProxy.read_body(actor: current_actor, knowledge_item: item)
    # #402 (Hans, 2026-05-28): `?hl=gelb,rot` filterte die Vorschau auf die
    # gewählten Highlight-Farben — SERVERSEITIG (nur die Marks).
    # #782 (Hans, 2026-06-29): Der Highlight-Filter läuft jetzt CLIENTSEITIG
    # (reply-search-Controller, gleicher Modus-Button wie die Suche: Alles /
    # ±1 Kontext / nur Treffer). Dafür den VOLLEN Body rendern, damit die
    # Kontext-Modi die Nachbarabsätze im DOM haben. Die aktiven Farben gehen
    # über params[:hl] an den Controller (siehe _detail).
    KnowledgeMarkdown.render(body, item: item)
  rescue FileProxy::FileNotFound
    "<em>Datei nicht auf Platte gefunden.</em>".html_safe
  end

  def binary_attachment?(item)
    path = item.file_path.to_s
    return false if path.blank?
    !path.downcase.end_with?(".md")
  end

  def document_embed_html(item)
    file_url     = file_knowledge_item_path(item.uuid)
    download_url = file_knowledge_item_path(item.uuid, download: 1)
    ext          = File.extname(item.file_path).downcase
    pdf          = ext == ".pdf"
    helpers.safe_join([
      helpers.tag.div(class: "flex items-center gap-3 mb-3 text-xs text-slate-600",
                      data: {
                        controller: "pdf-quote",
                        pdf_quote_url_value: quote_from_clipboard_knowledge_item_path(item.uuid)
                      }) do
        helpers.safe_join([
          helpers.tag.span(File.basename(item.file_path), class: "font-mono truncate"),
          helpers.button_tag("📋 Quote",
            type: "button",
            title: "Markierten Text per Zwischenablage in die Quotes-Sammlung anhängen",
            data: { action: "click->pdf-quote#paste" },
            class: "px-2 py-0.5 rounded border border-slate-200 hover:bg-slate-50 text-slate-700 cursor-pointer"),
          helpers.link_to("⬇ Download", download_url, class: "text-emerald-700 hover:underline")
        ])
      end,
      if pdf
        helpers.tag.iframe(nil, src: "#{file_url}#view=FitH",
                           class: "w-full h-[80vh] border border-slate-200 rounded bg-slate-50")
      elsif KnowledgeMarkdown::Embeds::IMAGE_EXTENSIONS.include?(ext)
        # #609: Bild-KIs zeigen ihr Bild inline (vorher: nur Download-Hinweis).
        helpers.tag.img(src: file_url, alt: item.title,
                        class: "max-w-full h-auto rounded border border-slate-200")
      else
        helpers.tag.p("Vorschau für #{ext}-Dateien nicht verfügbar — bitte Download.",
                      class: "text-sm text-slate-500 italic")
      end
    ])
  end
end
