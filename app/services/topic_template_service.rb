class TopicTemplateService
  class NotATemplateError < StandardError; end

  def self.instantiate(template_topic, new_name:, creator:, team_id: nil)
    raise NotATemplateError, "topic '#{template_topic.name}' is not a template" unless template_topic.template?

    ActiveRecord::Base.transaction do
      new_topic = Topic.create!(
        name:        new_name,
        slug:        generate_slug(new_name),
        description: template_topic.description,
        status:      :active,
        color:       template_topic.color,
        template:    false,
        creator:     creator,
        team_id:     team_id
      )

      task_mapping = {}
      positions_by_task = template_topic.task_topics.index_by(&:task_id)

      ordered_template_tasks(template_topic).each do |tmpl_task|
        task_mapping[tmpl_task.id] = clone_task(tmpl_task, creator: creator, mapping: task_mapping)
      end

      ordered_template_tasks(template_topic).each do |tmpl_task|
        cloned = task_mapping[tmpl_task.id]
        pos    = positions_by_task[tmpl_task.id]&.position || 0
        TaskTopic.create!(task: cloned, topic: new_topic, position: pos)
      end

      copy_dependencies(task_mapping)

      new_topic
    end
  end

  def self.ordered_template_tasks(topic)
    topic.tasks.order("task_topics.position ASC, tasks.id ASC")
  end
  private_class_method :ordered_template_tasks

  def self.clone_task(tmpl_task, creator:, mapping:)
    Task.create!(
      title:       tmpl_task.title,
      description: tmpl_task.description,
      status:      :open,
      priority:    tmpl_task.priority,
      due_date:    nil,
      completed_at: nil,
      assignee_id: nil,
      skip_default_assignee: true,   # Vorlagen-Klone bleiben bewusst unassigniert
      creator:     creator,
      parent_id:   tmpl_task.parent_id && mapping[tmpl_task.parent_id]&.id
    )
  end
  private_class_method :clone_task

  def self.copy_dependencies(task_mapping)
    original_ids = task_mapping.keys
    TaskDependency.where(predecessor_id: original_ids, successor_id: original_ids).find_each do |dep|
      TaskDependency.create!(
        predecessor:     task_mapping[dep.predecessor_id],
        successor:       task_mapping[dep.successor_id],
        dependency_type: dep.dependency_type
      )
    end
  end
  private_class_method :copy_dependencies

  def self.generate_slug(name)
    base = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-+|-+$/, "")
    base = "topic" if base.blank?
    candidate = base
    counter = 2
    while Topic.exists?(slug: candidate)
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    candidate
  end
  private_class_method :generate_slug
end
