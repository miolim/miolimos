module Inbox
  module Processors
    # AI-Transformation eines InboxItems via PromptTemplate. Nimmt den
    # Body des Items (raw_content oder einen verlinkten KI-Body) und
    # füttert ihn in einen LLM-Prompt; Ergebnis wird als neues KI
    # angelegt mit Backlink auf die Quelle.
    #
    # PromptTemplate kommt aus inbox_item.payload["prompt_template_slug"]
    # — die UI setzt das vor dem Run.
    class AiTransform < ProcessorBase
      def self.kind        = "ai_transform"
      def self.label       = "AI-Transformation (Zusammenfassung etc.)"
      def self.description = "Wendet ein PromptTemplate auf den Item-Inhalt an und legt ein neues KI mit dem LLM-Output an."

      def self.applies?(item)
        # AiTransform ist immer verfügbar — der User wählt den Template
        # explizit, kein Auto-Vorschlag.
        true
      end

      def process!(item, actor:)
        slug = item.payload["prompt_template_slug"].to_s
        template = PromptTemplate.find_by(slug: slug)
        raise "Kein PromptTemplate gewählt (payload.prompt_template_slug)" unless template

        input  = build_input_text(item)
        prompt = render_prompt(template.prompt_text, input: input,
                               source_url: item.source_url,
                               source_title: item.title)

        result = LlmActivity.track(
          kind:                 :inbox_ai_transform,
          actor:                actor,
          source_kind:          "inbox_item",
          source_id:            item.id.to_s,
          input_summary:        input,
          prompt_template_slug: template.slug,
          model:                template.default_model || Llm::ChatClient::DEFAULT_ANTHROPIC_MODEL
        ) do |activity|
          output = Llm::ChatClient.complete(
            prompt:    prompt,
            model:     template.default_model,
            system:    system_prompt(template),
            activity:  activity
          )
          raise "LLM lieferte leere Antwort" if output.blank?

          title = derive_title(output, template, item)
          # AI-Transformation produziert typischerweise eine Zusammen-
          # fassung der Source — also `:abstract` (whole-source,
          # paraphrasiert). #705 (b): bei output_format=html wird das KI als
          # HTML-Artefakt gerendert (sandboxed iframe).
          html = template.output_html?
          new_ki = FileProxy.create(
            actor:      actor,
            title:      title,
            item_type:  :abstract,
            content:    output.strip,
            tags:       (["ai-summary", template.slug] + (html ? ["html"] : [])).uniq
          )
          new_ki.update!(render_mode: "html") if html
          src_id = linked_source_id(item)
          new_ki.update!(bib_source_id: src_id)
          if src_id && (src = Source.find_by(id: src_id))
            FileProxy.merge_frontmatter!(actor: actor, knowledge_item: new_ki,
                                          bib_source: src.slug)
          end
          { output: output, result_kind: "knowledge_item", result_id: new_ki.uuid }
        end

        created_ki = KnowledgeItem.find_by(uuid: result[:result_id])
        record_result(item, knowledge_item: created_ki) if created_ki
      end

      private

      # Wenn das InboxItem schon ein KI erzeugt hat (z.B. via YouTube-
      # Processor lief vorher), nehmen wir dessen Body als Input — das
      # ist die typische Pipeline "YouTube → KI mit Transkript →
      # AI-Summary als zweites KI". Sonst raw_content.
      def build_input_text(item)
        prior_ki_uuid = Array(item.result["created"])
                          .find { |c| c["kind"] == "knowledge_item" }
                          &.dig("uuid")
        if prior_ki_uuid && (ki = KnowledgeItem.find_by(uuid: prior_ki_uuid))
          ki.body.to_s
        else
          item.raw_content.to_s
        end
      end

      def linked_source_id(item)
        prior_ki_uuid = Array(item.result["created"])
                          .find { |c| c["kind"] == "knowledge_item" }
                          &.dig("uuid")
        return nil unless prior_ki_uuid
        KnowledgeItem.find_by(uuid: prior_ki_uuid)&.bib_source_id
      end

      # Simple Mustache-Style: {{input}}, {{source_url}}, {{source_title}}.
      def render_prompt(template, **vars)
        out = template.dup
        vars.each { |k, v| out.gsub!("{{#{k}}}", v.to_s) }
        out
      end

      # #705 (b): System-Prompt je nach Ausgabeformat. HTML-Output wird im
      # Blade in einem isolierten Sandbox-iframe gerendert (allow-scripts,
      # kein same-origin), darf also reich/interaktiv sein.
      def system_prompt(template)
        if template.output_html?
          "Antworte ausschliesslich mit einem vollstaendigen, eigenstaendigen HTML-Dokument " \
          "(idealerweise beginnend mit <!DOCTYPE html>). Inline-CSS und -JavaScript sind erlaubt " \
          "und erwuenscht fuer eine reiche, ggf. interaktive Darstellung. Das HTML wird in einem " \
          "isolierten Sandbox-iframe gerendert (kein Zugriff auf die App). Keine Markdown-Syntax, " \
          "keine Code-Fences, keine Erklaerungen drumherum."
        else
          "Antworte ausschließlich mit Markdown-Inhalt. Kein Drumherum, keine Erklärungen."
        end
      end

      def derive_title(output, template, item)
        if template.output_html?
          m = output.match(%r{<title[^>]*>(.+?)</title>}im) ||
              output.match(%r{<h1[^>]*>(.+?)</h1>}im)
          if m
            t = m[1].gsub(/<[^>]+>/, "").strip
            return t unless t.empty?
          end
        else
          h1 = output.lines.find { |l| l.start_with?("# ") }
          return h1.sub(/\A#\s+/, "").strip if h1
        end

        base = item.title.presence || item.source_url.presence || "Inbox-Item"
        "#{template.name}: #{base}"
      end
    end
  end
end
