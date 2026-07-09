# Klassifiziert eine Communication gegen aktive non-template Topics
# per Cosine-Similarity von Embeddings (bge-m3 via Ollama).
#
# Ergebnis einer .suggest-Aufruf:
#   {
#     top:          { topic: <Topic>, score: 0.0..1.0 } | nil,
#     alternatives: [{ topic:, score: }, ...],  # sortiert absteigend
#     decision:     :auto_assign | :suggest | :skip
#   }
#
# Schwellwerte (tunable):
#   AUTO-ASSIGN: score >= 0.70 UND margin zum 2. Platz >= 0.08
#   SUGGEST:     score >= 0.45 (und kein AUTO-Treffer)
#   SKIP:        sonst
#
# Topic-Embeddings werden gecacht (Rails.cache), Key enthält updated_at
# damit Änderungen am Topic die Vektoren invalidieren.
module Classifiers
  class EmailTopicSuggester
    AUTO_THRESHOLD   = 0.70
    AUTO_MARGIN      = 0.08
    SUGGEST_THRESHOLD = 0.45

    def initialize(embedder: OllamaEmbedder.new, topics: nil)
      @embedder = embedder
      @topics = topics || Topic.non_templates.active.to_a
    end

    # Hauptmethode. Liefert Hash mit :top, :alternatives, :decision.
    # Bei Ollama-Ausfall → { top: nil, alternatives: [], decision: :skip, error: ... }
    def suggest(communication)
      suggest_text(email_text(communication))
    end

    # #934 Stufe 2: dieselbe Klassifikation für beliebigen Text (z.B. die
    # Extraktion eines Eingangs-Dokuments) — Mail-unabhängig nutzbar.
    def suggest_text(text)
      return skip_result("empty text") if text.blank?

      mail_vec = @embedder.embed(text)
      return skip_result("embedder unavailable") unless mail_vec

      scores = @topics.filter_map do |topic|
        vec = topic_embedding(topic)
        next unless vec
        { topic: topic, score: cosine(mail_vec, vec) }
      end.sort_by { |s| -s[:score] }

      return skip_result("no topics") if scores.empty?

      top = scores.first
      second = scores[1]&.dig(:score) || 0.0
      margin = top[:score] - second

      decision =
        if top[:score] >= AUTO_THRESHOLD && margin >= AUTO_MARGIN
          :auto_assign
        elsif top[:score] >= SUGGEST_THRESHOLD
          :suggest
        else
          :skip
        end

      { top: top, alternatives: scores.drop(1).first(3), decision: decision }
    end

    # Persistiert das Ergebnis auf der Communication:
    # - :auto_assign → CommunicationTopic anlegen + decided_at setzen
    # - :suggest     → suggested_topic + score (nicht angewandt)
    # - :skip        → nichts
    def apply(communication, result = nil)
      result ||= suggest(communication)
      return result if result[:decision] == :skip

      top = result[:top]
      return result unless top

      case result[:decision]
      when :auto_assign
        ActiveRecord::Base.transaction do
          CommunicationTopic.find_or_create_by!(communication: communication, topic: top[:topic])
          communication.update_columns(
            suggested_topic_id:         top[:topic].id,
            suggested_topic_score:      top[:score],
            suggested_topic_decided_at: Time.current
          )
        end
      when :suggest
        communication.update_columns(
          suggested_topic_id:         top[:topic].id,
          suggested_topic_score:      top[:score],
          suggested_topic_decided_at: nil
        )
      end
      result
    end

    private

    def email_text(comm)
      # Subject zweimal gewichten (kurz, stark wegweisend), dann Body
      # auf 500 Zeichen begrenzt — genug Kontext, ohne Embeddings
      # unnötig zu verwässern.
      parts = [comm.subject, comm.subject, comm.body.to_s.strip[0, 500]]
      parts.compact.reject(&:blank?).join("\n\n")
    end

    def topic_text(topic)
      # Name + Description ergeben zusammen ein brauchbares Topic-Profil.
      [topic.name, topic.description.to_s.strip].reject(&:blank?).join(" — ")
    end

    def topic_embedding(topic)
      key = "topic_embedding:#{topic.id}:v1:#{topic.updated_at.to_i}"
      Rails.cache.fetch(key, expires_in: 30.days) do
        @embedder.embed(topic_text(topic))
      end
    end

    def cosine(a, b)
      return 0.0 if a.blank? || b.blank? || a.length != b.length
      dot = 0.0
      na  = 0.0
      nb  = 0.0
      a.each_with_index do |x, i|
        y = b[i]
        dot += x * y
        na += x * x
        nb += y * y
      end
      return 0.0 if na.zero? || nb.zero?
      dot / (Math.sqrt(na) * Math.sqrt(nb))
    end

    def skip_result(reason)
      { top: nil, alternatives: [], decision: :skip, reason: reason }
    end
  end
end
