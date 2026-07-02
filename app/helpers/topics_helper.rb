# #203 Phase E.6: Topic-Marker (Dot/Triangle) + next_step-Queries.
module TopicsHelper
  def topic_dot(topic)
    color = topic.color.presence || "#94a3b8"
    content_tag :span, "", class: "inline-block w-2 h-2 rounded-full shrink-0", style: "background: #{color}"
  end

  # Topic-Marker für Listen / Sidebar. Wenn next_step gesetzt ist, wird
  # ein nach rechts zeigendes, gefülltes Dreieck statt eines Kreises
  # gerendert — visualisiert auf einen Blick: dieses Topic hat einen
  # angepinnten nächsten Schritt (Sidebar) bzw. diese Aufgabe IST der
  # nächste Schritt für ihr Topic (Tasks-Liste).
  def topic_marker(topic, next_step: false, milestone: false, size: :sm, title: nil)
    color = topic.color.presence || "#94a3b8"
    px    = size == :md ? "w-3 h-3" : "w-2 h-2"
    # #572: Meilensteine als Raute statt Kreis (next_step-Dreieck gewinnt).
    if milestone && !next_step
      return content_tag(:span, "",
        class: "inline-block shrink-0 rotate-45 #{size == :md ? 'w-2.5 h-2.5' : 'w-1.5 h-1.5'}",
        style: "background: #{color}",
        title: title)
    end
    if next_step
      # Polygon mit innerem Padding (statt die viewBox voll auszufüllen),
      # damit das Dreieck visuell so groß wirkt wie der Kreis-Marker
      # gleicher Bounding-Box. Ein Kreis füllt eine Quadrat-Box nur zu
      # ~78% (π/4); ein bündiges Dreieck wirkt sonst optisch zu groß.
      tag.svg(class: "inline-block #{px} shrink-0", viewBox: "0 0 10 10",
              xmlns: "http://www.w3.org/2000/svg",
              "aria-label": title) do
        tag.polygon(points: "2,2 7,5 2,8", fill: color)
      end
    else
      content_tag :span, "",
        class: "inline-block #{px} rounded-full shrink-0",
        style: "background: #{color}",
        title: title
    end
  end

  # Hat ein bestimmtes Topic einen angepinnten next_step? Memoized pro
  # Request mit *einer* Query — verhindert N+1 in der Sidebar (eine
  # Sidebar listet alle aktiven Topics auf).
  def topic_has_next_step?(topic)
    @_topic_ids_with_next_step ||= TaskTopic.where(next_step: true)
                                            .distinct
                                            .pluck(:topic_id)
                                            .to_set
    @_topic_ids_with_next_step.include?(topic.id)
  end

  # Ist eine Aufgabe der next_step für das gegebene Topic? Setzt voraus,
  # dass task.task_topics bereits geladen ist (Controller-side
  # `includes(:task_topics)`), sonst gibt's für jede Row eine Extra-Query.
  def task_next_step_for?(task, topic)
    return false if topic.nil?
    task.task_topics.any? { |tt| tt.topic_id == topic.id && tt.next_step? }
  end
end
