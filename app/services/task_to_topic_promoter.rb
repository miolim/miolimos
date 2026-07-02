# #150 Phase B: wandelt eine Task in ein neues Topic um.
#
# Use-Case: eine ursprünglich kleine Aufgabe wächst zu einem Mini-Projekt
# mit Recherche, Subtasks, eigenem Output. Statt sie umständlich
# weiterzuführen, befördert der User sie zum Topic — alle Sub-Tasks
# werden zu Top-Level-Tasks unter dem neuen Topic, verknüpfte KIs/
# Wartepunkte hängen am Topic. Die alte Task wird als done geschlossen
# und trägt einen Verweis aufs neue Topic.
#
# Was wird transferiert:
#   - Subtasks    → Top-Level-Tasks mit task_topics-Verbindung
#   - mentioned_kis → topic.knowledge_item_topics
#   - awaitings   → topic.awaiting_topics
#
# Was NICHT transferiert wird:
#   - Sources (Topics haben keine direkte Source-Verknüpfung)
#   - Attachments (Task-spezifisch, kein Topic-Pendant im Modell)
#   - Bestehende Task-Topic-Verknüpfungen (sauberer Cut: das neue Topic
#     ist eigenständig, nicht Sub-Topic des alten — kann der User per
#     Hand ändern, wenn gewünscht)
class TaskToTopicPromoter
  def self.call(task, actor:)
    new(task, actor: actor).call
  end

  def initialize(task, actor:)
    @task  = task
    @actor = actor
  end

  def call
    topic = nil
    Topic.transaction do
      topic = create_topic
      promote_subtasks(topic)
      transfer_mentioned_kis(topic)
      transfer_awaitings(topic)
      close_original_task(topic)
    end
    topic
  end

  private

  def create_topic
    Topic.create!(
      name:        @task.title,
      slug:        unique_slug,
      description: @task.description,
      creator:     @actor,
      status:      :active
    )
  end

  # Slug nach dem Schema-Validator (lowercase + Bindestriche); bei
  # Kollision durchnummerieren.
  def unique_slug
    base = @task.title.to_s.parameterize.presence || "topic-#{@task.id}"
    slug = base
    i = 2
    while Topic.exists?(slug: slug)
      slug = "#{base}-#{i}"
      i += 1
    end
    slug
  end

  def promote_subtasks(topic)
    @task.subtasks.find_each do |sub|
      sub.update_column(:parent_id, nil)
      topic.task_topics.find_or_create_by!(task_id: sub.id)
    end
  end

  def transfer_mentioned_kis(topic)
    @task.mentioned_kis.distinct.find_each do |ki|
      topic.knowledge_item_topics.find_or_create_by!(knowledge_item_uuid: ki.uuid)
    end
  end

  def transfer_awaitings(topic)
    @task.awaitings.find_each do |a|
      topic.awaiting_topics.find_or_create_by!(awaiting_id: a.id)
    end
  end

  def close_original_task(topic)
    link_note = "Wurde umgewandelt in Thema: [#{topic.name}](/topics/#{topic.slug})"
    new_desc = [@task.description.to_s.strip.presence, link_note].compact.join("\n\n")
    @task.update!(
      description:  new_desc,
      status:       :done,
      completed_at: Time.current
    )
  end
end
