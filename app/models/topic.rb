class Topic < ApplicationRecord
  belongs_to :creator, class_name: "Actor"
  belongs_to :team, optional: true

  # #602 S1: Multi-User-Sichtbarkeit. Das Topic ist die Freigabe-Einheit:
  # members_only = nur Mitglieder (+ Ersteller/Admins), internal_public =
  # alle internen Nutzer (Glossar, Handbuch, Vorlagen). Inhalte erben die
  # Sichtbarkeit über die visible_to-Scopes ihrer Modelle (VisibleVia).
  enum :visibility, { members_only: 0, internal_public: 1 }, default: :members_only

  has_many :topic_memberships, dependent: :destroy
  has_many :members, through: :topic_memberships, source: :actor

  # DER zentrale Sichtbarkeits-Filter für Topics. #602 S3: Mitgliedschaft
  # VERERBT sich an Sub-Topics — wer im Eltern-Thema Mitglied ist, sieht
  # den ganzen Teilbaum (rekursive CTE; Zyklen verhindert die
  # parent_topic-Validierung).
  MEMBER_TREE_SQL = <<~SQL.freeze
    WITH RECURSIVE member_tree AS (
      SELECT tm.topic_id AS id FROM topic_memberships tm WHERE tm.actor_id = ?
      UNION
      SELECT t.id FROM topics t JOIN member_tree mt ON t.parent_topic_id = mt.id
    ) SELECT id FROM member_tree
  SQL

  scope :visible_to, ->(actor) {
    next all  if actor&.visibility_exempt?
    next none if actor.nil?
    where(visibility: :internal_public)
      .or(where(creator_id: actor.id))
      .or(where("topics.id IN (#{MEMBER_TREE_SQL})", actor.id))
  }

  # #602 S2: INHALTE schreiben (via VisibleVia#writable_by?) dürfen
  # Admin/Agent, Ersteller und Mitglieder mit Rolle Bearbeiter/
  # Verantwortlicher. Nur-Betrachter und intern-Öffentliches ohne
  # Mitgliedschaft: lesen ja, schreiben nein.
  def writable_by?(actor)
    return true if actor.nil? || actor.visibility_exempt?
    return true if creator_id == actor.id
    # #602 S3: Gäste lesen nur — eine Mitgliedschaft gibt ihnen nie
    # Schreibrechte, egal welche Mitglieds-Rolle eingetragen ist.
    return false if actor.guest?
    (effective_membership_role_value(actor) || -1) >= TopicMembership.roles[:editor]
  end

  # #602 S3: wirksame Mitglieds-Rolle = stärkste Rolle auf diesem Topic
  # ODER einem Vorfahren (Mitgliedschaft vererbt sich abwärts).
  # Rückgabe: Integer-Enum-Wert (viewer 0 / editor 1 / owner 2) oder nil.
  def effective_membership_role_value(actor)
    TopicMembership.where(actor_id: actor.id,
                          topic_id: [id] + ancestor_topics.map(&:id))
                   .pluck(:role)
                   .map { |r| TopicMembership.roles.fetch(r.to_s, r.to_i) }
                   .max
  end

  # #602 S3: Das THEMA selbst (Name/Status/Sichtbarkeit/Mitglieder/
  # Löschen) verwaltet nur, wer es verantwortet: Admin, Ersteller oder
  # owner-Mitglied — Bearbeiter bearbeiten Inhalte, nicht das Thema.
  def manageable_by?(actor)
    return true if actor.nil? || actor.visibility_exempt?
    return false if actor.guest?
    creator_id == actor.id ||
      effective_membership_role_value(actor) == TopicMembership.roles[:owner]
  end

  before_update  :enforce_visibility_write_guard
  before_destroy :enforce_visibility_write_guard

  def enforce_visibility_write_guard
    return if manageable_by?(Current.actor)
    raise AccessGate::Unauthorized,
          "#{Current.actor.name} darf Thema „#{name}“ nicht verwalten (nur Verantwortliche)"
  end
  private :enforce_visibility_write_guard

  # #150: Sub-Topics. Parent ist optional (Top-Level-Topic), Kinder bleiben
  # bei Parent-Delete als Top-Level zurück.
  belongs_to :parent_topic, class_name: "Topic", optional: true
  has_many :sub_topics, class_name: "Topic", foreign_key: :parent_topic_id, dependent: :nullify

  has_many :task_topics, dependent: :destroy
  has_many :tasks, through: :task_topics

  has_many :knowledge_item_topics, dependent: :destroy
  has_many :knowledge_items, through: :knowledge_item_topics

  # #325 (Hans, 2026-05-24): optionaler Work-Tree pro Topic. Wenn leer
  # → reine Themen-Sammlung. Wenn gefuellt → Manuskript-in-Arbeit
  # bzw. publiziertes Werk.
  # #592: Bäume sind verallgemeinert (TopicTree) — Work-Tree = kind=work,
  # Zweckgeflecht = kind=purpose; mehrere Bäume je Topic möglich.
  # work_nodes (Knoten ALLER Bäume) bleibt für Zähler/Cascade bestehen.
  has_many :topic_trees, dependent: :destroy
  has_many :work_nodes, dependent: :destroy
  def default_work_tree
    topic_trees.work.first || topic_trees.create!(kind: "work", position: 1)
  end
  # #740 (Hans): baum-agnostisch — ein Baum ist Gliederung UND Mittel-
  # Zweck-Struktur zugleich, beides aus demselben Baum renderbar. Fallback
  # auf den ersten Baum mit Knoten (egal welche frühere „Art"), damit auch
  # ein reines Mittel-Zweck-Topic ein Werk-Render bekommt.
  def work_tree_roots
    tree = topic_trees.work.first || topic_trees.joins(:nodes).order(:position).first
    tree ? tree.roots : WorkNode.none
  end
  def has_tree? = topic_trees.joins(:nodes).exists?

  has_many :communication_topics, dependent: :destroy
  has_many :communications, through: :communication_topics

  has_many :awaiting_topics, dependent: :destroy
  has_many :awaitings, through: :awaiting_topics

  # #155 Phase 5c: Recherche-Quellen mit Relevanz-Markierung.
  has_many :source_topics, dependent: :destroy
  has_many :research_sources, through: :source_topics, source: :source

  # #533 Phase 1 (Hans, 2026-06-07): ein Topic wird (optional) zum PROJEKT,
  # indem ein Kunde (Person/Org-KI) verknüpft wird. Kein separates
  # Project-/Customer-Modell — die Arbeit hängt ohnehin schon am Topic.
  # `billable` markiert abrechenbare Projekte. Topics ohne Kunde bleiben
  # ganz normale Themen-Topics.
  belongs_to :customer, class_name: "KnowledgeItem",
    foreign_key: :customer_uuid, primary_key: :uuid, optional: true

  scope :projects, -> { where.not(customer_uuid: nil) }

  def project? = customer_uuid.present?

  enum :status, { active: 0, paused: 1, completed: 2, archived: 3 }, default: :active

  # #472 (Hans, 2026-06-02): research_question/research_kind entfernt —
  # Recherche-Topics laufen jetzt ueber Vorlagen/Tags (#471), Synthesen
  # ueber die Synthese-KI-Vorlagen statt research_kind-gesteuert.

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "must be lowercase with hyphens" }
  validate :parent_topic_not_self_or_descendant

  # #170: Quick-Add aus der Sidebar schickt nur `name` + `color`. Damit
  # die slug-presence-Validierung greift, leiten wir den Slug vor der
  # Validierung aus dem Namen ab. Wenn der Aufrufer explizit einen Slug
  # mitschickt, bleibt der unangetastet.
  before_validation :derive_slug_from_name, on: :create

  def derive_slug_from_name
    return if slug.present?
    return if name.blank?
    self.slug = name.to_s.parameterize
  end

  scope :top_level, -> { where(parent_topic_id: nil) }

  # #435 (Hans, 2026-06-01): Zuletzt geoeffnete Topics fuer die Sidebar.
  # "Geoeffnet" = der Actor hat (>=3s, via ActorView/view-tracker) entweder
  # das Topic selbst (Topic-Stack/-Card) oder ein Element des Topics
  # (Task/KnowledgeItem als Detail-Card) angeschaut. Sortiert nach juengster
  # Oeffnung, dedupliziert auf ein Topic. Liefert echte Topic-Records.
  def self.recently_opened_for(actor, limit: 5)
    return [] if actor.nil? || limit.to_i <= 0
    rows = ActorView.for_actor(actor)
                    .where(viewable_type: %w[Topic Task KnowledgeItem])
                    .order(viewed_at: :desc)
                    .limit(400)
                    .pluck(:viewable_type, :viewable_id, :viewed_at)
    task_ids = rows.filter_map { |t, id, _| id.to_i if t == "Task" }.uniq
    ki_uuids = rows.filter_map { |t, id, _| id if t == "KnowledgeItem" }.uniq

    task_map = TaskTopic.where(task_id: task_ids).pluck(:task_id, :topic_id)
                        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(tid, top), h| h[tid] << top }
    ki_map   = KnowledgeItemTopic.where(knowledge_item_uuid: ki_uuids).pluck(:knowledge_item_uuid, :topic_id)
                        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(u, top), h| h[u] << top }

    last_open = {} # topic_id => juengster viewed_at (rows sind desc -> erster gewinnt)
    rows.each do |type, id, at|
      topic_ids = case type
                  when "Topic"         then [id.to_i]
                  when "Task"          then task_map[id.to_i]
                  when "KnowledgeItem" then ki_map[id]
                  end
      Array(topic_ids).each { |tid| last_open[tid] ||= at }
    end

    ordered = last_open.sort_by { |_, at| at }.reverse.map(&:first)
    by_id   = non_templates.active.where(id: ordered).index_by(&:id)
    ordered.filter_map { |tid| by_id[tid] }.first(limit.to_i)
  end

  # Vorfahren-Kette von unmittelbarem Parent bis zum Root.
  def ancestor_topics
    list = []
    current = parent_topic
    while current && !list.include?(current)
      list << current
      current = current.parent_topic
    end
    list
  end

  # Alle Nachfahren rekursiv. Für Cycle-Check und Tree-View.
  def descendant_topics
    result = []
    queue  = sub_topics.to_a
    until queue.empty?
      t = queue.shift
      next if result.include?(t)
      result << t
      queue.concat(t.sub_topics.to_a)
    end
    result
  end

  scope :templates, -> { where(template: true) }
  scope :non_templates, -> { where(template: false) }

  # Route-Parameter ist der Slug (siehe routes.rb: resources :topics, param: :slug).
  def to_param
    slug
  end

  # Idempotent resolver used by FileProxy and KnowledgeIndexer: look up a
  # topic by slug, and if it does not exist, create a non-template active
  # topic owned by `creator`. Deriving the display name from the slug keeps
  # the slug-first convention from the architecture doc.
  def self.find_or_create_from_slug!(slug, creator:)
    find_by(slug: slug) || create!(
      slug:     slug,
      name:     slug.to_s.tr("-", " ").split.map(&:capitalize).join(" "),
      creator:  creator,
      status:   :active,
      template: false
    )
  end

  # #421 (Hans, 2026-05-31): die `tasks`-through-Assoziation joint
  # `task_topics` bereits mit `topic_id = id` — ein zusaetzliches
  # `.joins(:task_topics)` legt einen zweiten unaliasierten Join
  # (`task_topics_tasks`) ohne Filter an, sodass jede Task mit N
  # Topic-Verknuepfungen N-fach in der Liste auftaucht. Reine
  # through-Assoziation nutzen.
  def ordered_tasks
    tasks.order("task_topics.position ASC")
  end

  # Explizit gesetzter Next-Step für dieses Thema (oder nil).
  # Überschreibt das frühere Heuristik-Konzept "erste offene Task".
  def next_step_task
    tasks.where(task_topics: { next_step: true }).first
  end

  private

  def parent_topic_not_self_or_descendant
    return if parent_topic_id.blank?
    if persisted? && parent_topic_id == id
      errors.add(:parent_topic_id, "kann nicht das Topic selbst sein")
      return
    end
    if persisted? && descendant_topics.any? { |t| t.id == parent_topic_id }
      errors.add(:parent_topic_id, "kann kein Sub-Topic sein (Zyklus)")
    end
  end
end
