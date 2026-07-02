# Audit-Log für LLM-getriebene Operationen (Recherche an Absätzen,
# Inbox-AI-Transform, YouTube-Whisper/Strukturierung/Zusammenfassung).
# Schreibt sich von den jeweiligen Jobs/Processors selbst, sodass
# Settings → LLM-Aktivität einen Verlauf zeigen kann (inkl. Failures
# und „Erneut versuchen").
class LlmActivity < ApplicationRecord
  belongs_to :actor

  STATUSES = %w[queued running succeeded failed].freeze
  KINDS = %w[
    paragraph_research
    inbox_ai_transform
    inbox_youtube_whisper
    inbox_youtube_diarize
    inbox_youtube_structure
    inbox_youtube_summary
  ].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :kind,   inclusion: { in: KINDS }

  scope :recent,      -> { order(created_at: :desc) }
  scope :by_status,   ->(s) { where(status: s) if s.present? }
  scope :by_kind,     ->(k) { where(kind: k)   if k.present? }
  scope :failed,      -> { where(status: "failed") }
  scope :succeeded,   -> { where(status: "succeeded") }

  # Lifecycle-Helfer: aufeinanderfolgende Aufrufe erweitern den Datensatz,
  # ohne Caller-Logik zu duplizieren. Alle setzen automatisch passende
  # Timestamps.
  def mark_running!(model: nil)
    update!(status: "running", started_at: Time.current,
            model: model || self.model)
  end

  def mark_succeeded!(output: nil, result_kind: nil, result_id: nil,
                      input_tokens: nil, output_tokens: nil, cost_eur: nil)
    update!(
      status: "succeeded",
      completed_at: Time.current,
      output_summary: output&.to_s&.truncate(2_000),
      result_kind: result_kind || self.result_kind,
      result_id:   result_id   || self.result_id,
      input_tokens:  input_tokens  || self.input_tokens,
      output_tokens: output_tokens || self.output_tokens,
      cost_eur:      cost_eur      || self.cost_eur
    )
  end

  def mark_failed!(error)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_message: error.to_s.truncate(2_000)
    )
  end

  # Klassen-Wrapper für „LLM-Operation tracken": legt einen LlmActivity
  # an und führt den Block in `mark_running` aus. Block-Rückgabewert
  # wird in `mark_succeeded` gespeichert; Exceptions in `mark_failed`
  # erzeugt und propagiert (damit Solid Queue sein Retry macht).
  def self.track(kind:, actor:, source_kind: nil, source_id: nil,
                 input_summary: nil, prompt_template_slug: nil, model: nil)
    activity = create!(
      kind:                 kind.to_s,
      actor:                actor,
      status:               "queued",
      source_kind:          source_kind,
      source_id:            source_id,
      input_summary:        input_summary&.to_s&.truncate(2_000),
      prompt_template_slug: prompt_template_slug,
      model:                model
    )
    activity.mark_running!(model: model)
    begin
      result = yield activity
      if result.is_a?(Hash)
        activity.mark_succeeded!(**result.symbolize_keys.slice(
          :output, :result_kind, :result_id, :input_tokens, :output_tokens, :cost_eur
        ))
      else
        activity.mark_succeeded!(output: result.to_s)
      end
      result
    rescue => e
      activity.mark_failed!("#{e.class}: #{e.message}")
      raise
    end
  end

  def duration_seconds
    return nil unless started_at && completed_at
    (completed_at - started_at).to_i
  end

  # Reicht den Original-Job basierend auf source_kind/source_id und kind
  # erneut bei Solid Queue ein. Liefert true bei erfolgreichem Enqueue,
  # false wenn die Quelle nicht (mehr) auflösbar ist. Kein Status-Reset
  # an der bestehenden Activity — der erneute Job-Run legt seine eigene
  # neue Activity an, sodass beide Versuche im Verlauf nebeneinander
  # stehen bleiben.
  def retry!
    case kind
    when "paragraph_research"
      uuid, anchor = source_id.to_s.split("#", 2)
      return false if uuid.blank? || anchor.blank?
      ParagraphResearchJob.perform_later(uuid, anchor, "", actor_id)
      true
    when "inbox_ai_transform", "inbox_youtube_whisper", "inbox_youtube_diarize",
         "inbox_youtube_structure", "inbox_youtube_summary"
      item = InboxItem.find_by(id: source_id)
      return false unless item
      processor_kind = item.processor_kind.presence || item.suggested_processor_kind
      ProcessInboxItemJob.perform_later(item.id, processor_kind, actor_id)
      true
    else
      false
    end
  end
end
