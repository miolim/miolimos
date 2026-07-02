# Asynchroner LLM-Recherche-Job, der zu einem Absatz-Anker einer KI
# eine eigenständige Notiz erzeugt. Der Body der neuen Notiz beginnt
# mit der ausgeschriebenen Anker-Referenz (gleiche Konvention wie
# manuelle Comments via comment_at) — danach folgt das LLM-Ergebnis.
#
# Prompt-Template: PromptTemplate mit Slug `paragraph_research`. In den
# Settings editierbar; wenn leer/nicht vorhanden, fällt der Job auf einen
# eingebauten Default zurück. Der Template-Text kann zwei Platzhalter
# enthalten: {{paragraph}} und {{hints}}.
class ParagraphResearchJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  # Anthropic / OpenAI können kurz "overloaded" (HTTP 529 / 429) liefern,
  # ebenso können Net::Read-Timeouts beim Streaming auftauchen. Beides
  # ist transient — polynomial Backoff über 4 Versuche reicht in der
  # Praxis aus. Wenn alle Versuche scheitern, landet der Job in
  # solid_queue_failed_executions; der User kann ihn dort manuell
  # neu triggern (oder einfach den Recherche-Button nochmal drücken).
  retry_on Llm::ChatClient::UnavailableError,
           wait: :polynomially_longer, attempts: 4
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 3

  TEMPLATE_SLUG = "paragraph-research".freeze
  DEFAULT_TEMPLATE = <<~PROMPT.freeze
    Du bekommst einen Absatz aus einer Wissens-Notiz. Recherchiere zum
    Inhalt dieses Absatzes und liefere eine sachlich-prägnante Zusammen-
    fassung der wichtigsten Hintergründe, Fakten oder offenen Fragen.

    Format:
    - Sprache wie der Absatz.
    - Markdown, 200–500 Wörter.
    - Bei Bedarf Stichpunkte oder Zwischenüberschriften (### …).
    - Keine Vorrede ("Hier ist die Recherche zu …"), direkt in den Inhalt.
    - Wenn Hinweise gegeben sind, gehe besonders auf diese ein.

    {{hints}}

    --- ABSATZ ---
    {{paragraph}}
  PROMPT

  def perform(item_uuid, anchor, hints, actor_id)
    item  = KnowledgeItem.find_by(uuid: item_uuid)
    actor = Actor.find_by(id: actor_id)
    return unless item && actor

    Current.set(actor: actor) do
      paragraph = KnowledgeBlockAnchor.new(item, actor: actor).text_at(anchor)
      return if paragraph.blank?

      input_summary = hints.present? ? "Hinweise: #{hints}\n\n#{paragraph}" : paragraph

      LlmActivity.track(
        kind:                 :paragraph_research,
        actor:                actor,
        source_kind:          "knowledge_item",
        source_id:            "#{item.uuid}##{anchor}",
        input_summary:        input_summary,
        prompt_template_slug: TEMPLATE_SLUG,
        model:                Llm::ChatClient::DEFAULT_ANTHROPIC_MODEL
      ) do |activity|
        prompt = build_prompt(paragraph, hints)
        answer = Llm::ChatClient.complete(prompt: prompt, max_tokens: 4_096, activity: activity).to_s.strip
        next { output: "" } if answer.blank?

        title = "Recherche zu: #{paragraph.split(/\s+/).first(6).join(" ")}".truncate(80)
        body  = "[[#{item.uuid}^#{anchor}|↳ #{item.title}]]\n\n#{answer}\n"
        ki = FileProxy.create(
          actor:     actor,
          title:     title,
          item_type: :note,
          content:   body,
          topics:    [], contacts: [],
          tags:      ["recherche"]
        )
        { output: answer, result_kind: "knowledge_item", result_id: ki.uuid }
      end
    end
  end

  private

  def build_prompt(paragraph, hints)
    template = PromptTemplate.find_by(slug: TEMPLATE_SLUG)&.prompt_text.presence ||
               DEFAULT_TEMPLATE
    hints_block = hints.present? ? "Zusätzliche Hinweise vom Nutzer:\n#{hints}" : ""
    template
      .gsub("{{paragraph}}", paragraph)
      .gsub("{{hints}}",     hints_block)
  end
end
