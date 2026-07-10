class Task < ApplicationRecord
  # #602 S1: sichtbar = eigene/zugewiesene Tasks + Tasks an sichtbaren Topics.
  include VisibleVia
  visible_via join: "TaskTopic", join_fk: :task_id,
              owner_columns: [:creator_id, :assignee_id]

  belongs_to :creator, class_name: "Actor"
  belongs_to :assignee, class_name: "Actor", optional: true
  belongs_to :parent, class_name: "Task", optional: true
  belongs_to :communication, optional: true
  belongs_to :inbox_item, optional: true
  # #230: pro Inbox-Lauf markiert sich der gerade arbeitende Actor als
  # wip_actor; geclearted am Lauf-Ende (Hans' explizite Bitte: nicht
  # bis status=done halten, sondern nur waehrend des aktuellen Schubs).
  belongs_to :wip_actor, class_name: "Actor", optional: true

  has_many :subtasks, class_name: "Task", foreign_key: :parent_id, dependent: :nullify

  has_many :task_topics, dependent: :destroy
  has_many :topics, through: :task_topics

  has_many :task_mentions, dependent: :destroy
  has_many :mentioned_kis, through: :task_mentions, source: :mentioned

  # #480 Inc.3 (Hans, 2026-06-03): Anker in der Description (Highlight +
  # Block-Anker) — Lookup fuer `[[^anker]]`-Wikilinks auf Task-Absaetze.
  has_many :task_anchors, dependent: :destroy

  has_many :task_sources, dependent: :destroy
  has_many :sources, through: :task_sources

  has_many :outgoing_dependencies, class_name: "TaskDependency",
    foreign_key: :predecessor_id, dependent: :destroy
  has_many :incoming_dependencies, class_name: "TaskDependency",
    foreign_key: :successor_id, dependent: :destroy

  has_many :successors, through: :outgoing_dependencies, source: :successor
  has_many :predecessors, through: :incoming_dependencies, source: :predecessor

  has_many :awaitings, dependent: :nullify

  # #676 (Hans, 2026-06-13): einen Recherche-Task zu löschen ist der Weg,
  # eine Entitäts-Recherche abzubrechen — der zugehörige
  # WikilinkResearchJob (Träger des ⏳-Indikators) muss mit weg, sonst
  # bleibt die Sanduhr stehen und zeigt auf einen 404-Task.
  has_many :wikilink_research_jobs, dependent: :destroy

  has_many :attachments, -> { order(:created_at) }, class_name: "TaskAttachment", dependent: :destroy

  # #953: Backlinks — KIs (Notizen, Antworten anderer Aufgaben/KIs) und
  # Aufgaben (Beschreibung, #953 Folge), die diese Aufgabe per [[#id]]
  # referenzieren. Incoming-Rows bleiben bei Task-Löschung stehen (der
  # Link im Quell-Body existiert ja weiter und rendert dann als „nicht
  # gefunden"); die Abfrage läuft immer von der Task-Seite.
  has_many :incoming_references, class_name: "KnowledgeItemReference",
    foreign_key: :target_task_id

  # #953 Folge: Referenzen AUS der eigenen Beschreibung ([[#id]]/[[Titel]]).
  has_many :outgoing_references, class_name: "KnowledgeItemReference",
    foreign_key: :source_task_id, dependent: :delete_all
  after_save :reindex_description_references, if: :saved_change_to_description?

  # Backlink-Quellen fürs Detail-Blade: eigene Antworten DIESER Aufgabe
  # zählen nicht (Selbst-Erwähnung im eigenen Thread ist Rauschen).
  def backlink_sources
    incoming_references.includes(:source, :source_task)
      .filter_map(&:source_object).uniq
      .reject { |src| src.is_a?(KnowledgeItem) && src.reply? && src.parent_type == "Task" && src.parent_id_int == id }
  end

  has_many :comments, -> { ordered }, class_name: "TaskComment", dependent: :destroy

  # #384 Phase 3b (Hans, 2026-05-27): Reply-KIs als universelle
  # Beitrags-Form. Polymorpher Parent: parent_type="Task",
  # parent_id_int=task.id. Aktuell PARALLEL zu task_comments — neuer
  # Reply-Flow schreibt hier rein, alte TaskComments werden in Phase
  # 3c migriert + die Tabelle dann deprecated.
  has_many :replies, -> {
    where(parent_type: "Task", item_type: KnowledgeItem.item_types[:reply])
      .order(:created_at)
  }, class_name: "KnowledgeItem", foreign_key: :parent_id_int, dependent: :destroy

  # Idempotentes Bulk-Mark-as-read: alle Comments dieses Tasks für
  # den gegebenen Actor markieren. Wird von Web- und API-Show
  # aufgerufen, sobald jemand das Detail öffnet.
  def mark_comments_read!(actor)
    return unless actor
    now = Time.current
    rows = comments.pluck(:id).map { |cid| { actor_id: actor.id, task_comment_id: cid, read_at: now, created_at: now, updated_at: now } }
    return if rows.empty?
    CommentRead.insert_all(rows, unique_by: %i[actor_id task_comment_id])
  end

  # AuditLog#readonly? ist true → destroy würde scheitern. delete_all
  # umgeht die AR-Instanzen und nutzt SQL-DELETE direkt.
  has_many :audit_logs, as: :auditable, dependent: :delete_all

  enum :status, { open: 0, done: 1 }, default: :open
  enum :priority, { low: 0, normal: 1, high: 2, urgent: 3 }, default: :normal

  # Asana-style: per-User "wann packe ich das an?". Orthogonal zu priority
  # (Wichtigkeit) und due_date (harte Deadline). nil = Eingang (Triage).
  # Explicit attribute type, weil Rails 8.1 sonst zur Class-Load-Zeit den
  # DB-Column-Type nachschlägt — in Production mit kaltem Schema-Cache
  # fliegt das mit "Undeclared attribute type for enum".
  attribute :commitment, :integer
  enum :commitment, { today: 0, soon: 1, later: 2 }, suffix: true

  include Auditable
  # #411 Iter 2 (Hans, 2026-05-30): published_at mit-tracken, damit
  # Veroeffentlichen und Pausieren im Aktivitaets-Log erscheinen.
  audited %w[status title assignee_id priority due_date commitment published_at]

  # Wenn true gesetzt, überspringt der before_validation-Callback die
  # Default-Zuweisung. TopicTemplateService nutzt das beim Klonen, weil
  # Vorlagen-Tasks bewusst unassigniert starten.
  attr_accessor :skip_default_assignee

  before_validation :default_assignee_to_current_actor, on: :create
  before_validation :default_published_at,                on: :create

  # Wird eine Task erledigt, kann sie nicht länger Next-Step eines Themas
  # sein — der Slot wird auto-geräumt.
  after_update :clear_next_step_if_done

  # #232/#564: Live-Broadcasts der Task-Listen — Callbacks + Methoden liegen
  # gesammelt in Task::LiveBroadcasts (app/models/task/live_broadcasts.rb).
  include LiveBroadcasts

  # #428 Phase 2 (Hans, 2026-05-31): tags-Array <-> zentrale Tag-Registry +
  # taggings synchron halten. Greift bei jeder Aenderung der tags-Spalte
  # (Web/API/Quickadd), die Array bleibt die Zuordnungs-Quelle.
  after_save    :sync_taggings, if: :saved_change_to_tags?
  after_destroy :remove_taggings

  # #480 Inc.3 (Hans, 2026-06-03): Description-Anker indizieren, sobald sich
  # die Beschreibung aendert (Highlight gesetzt, ensure_anchor, …).
  after_save    :sync_description_anchors, if: :saved_change_to_description?
  def sync_description_anchors = TaskAnchors::Sync.call(self)

  def sync_taggings  = TagSync.sync_task(self)
  def remove_taggings
    Tagging.where(taggable_type: "Task", taggable_id_int: id).delete_all
  end

  validates :title, presence: true
  validate :parent_not_in_own_subtree

  scope :root_tasks, -> { where(parent_id: nil) }

  # Tasks, die einem Template-Topic zugeordnet sind, sind Vorlagen und
  # gehören nur in die Vorlagenliste — nicht in /tasks oder Dashboard.
  scope :without_template_tasks, -> {
    where.not(id: TaskTopic.joins(:topic).where(topics: { template: true }).select(:task_id))
  }

  # Soft-Delete: discard! statt destroy! — Default-Scope blendet
  # gelöschte aus, with_discarded/discarded gibt sie wieder her.
  # Cron räumt nach 30 Tagen hart auf (siehe lib/tasks/cleanup.rake).
  default_scope { where(deleted_at: nil) }
  scope :with_discarded, -> { unscope(where: :deleted_at) }
  scope :discarded,      -> { with_discarded.where.not(deleted_at: nil) }

  # #167: Soft-Publish. published_at IS NULL = Entwurf. Web-UI zeigt
  # Drafts dem Ersteller; API-Inbox-Endpoints filtern auf published.
  scope :published, -> { where.not(published_at: nil) }
  scope :drafts,    -> { where(published_at: nil) }

  def discard!
    update!(deleted_at: Time.current)
  end

  def undiscard!
    update!(deleted_at: nil)
  end

  def discarded?
    deleted_at.present?
  end

  def draft?
    published_at.nil?
  end

  def publish!
    update!(published_at: Time.current) if draft?
  end

  # #411 (Hans, 2026-05-30): Pause = zurueck in den Entwurfsmodus.
  # Verlaengert die UX-Symmetrie zum Veroeffentlichen: Creator kann
  # eine bereits sichtbare Aufgabe wieder pausieren, sodass sie dem
  # Assignee nicht mehr angezeigt wird.
  def unpublish!
    update!(published_at: nil) if published_at.present?
  end

  # Alle Vorfahren (parent → parent.parent → …), nützlich für die
  # Zyklus-Prüfung und um im Subtask-Picker Ancestors auszublenden.
  def ancestor_ids
    ids = []
    current = parent
    seen = Set.new
    while current && !seen.include?(current.id)
      ids << current.id
      seen << current.id
      current = current.parent
    end
    ids
  end

  def blocked?
    predecessors.any? { |pred| !pred.done? }
  end

  # Simple open ↔ done toggle. Stamped completed_at geht/kommt mit.
  def toggle_done!
    if done?
      update!(status: :open, completed_at: nil)
    else
      update!(status: :done, completed_at: Time.current)
    end
  end

  # #232 (Hans, 2026-06-01): Sektion einer Task in der Wann-Gruppierung
  # (Eingang/Heute/Demnaechst/Spaeter). nil-commitment = Eingang. Public,
  # weil tasks/_row + der Section-Home-Controller (data-section-key) es nutzen.
  def time_section_key
    commitment.presence || "inbox"
  end

  private

  # #953 Folge: Wikilinks in der Beschreibung sofort in den Referenz-
  # Index schreiben (analog FileProxy.create/update für KI-Bodies).
  def reindex_description_references
    KnowledgeIndexer.index_task_description_references(self)
  end

  # Wer eine Aufgabe anlegt, kriegt sie standardmäßig selbst zugewiesen.
  # Quelle ist Current.actor (gesetzt im ApplicationController + API
  # BaseController). Explizite Zuweisung im Aufrufer hat Vorrang;
  # skip_default_assignee=true unterdrückt den Default ganz.
  def default_assignee_to_current_actor
    return if assignee_id.present? || skip_default_assignee
    self.assignee = Current.actor if Current.actor
  end

  # #167: Default-Publish-State. AgentActor-Assignees starten als
  # Entwurf (Hans braucht Zeit für die Beschreibung), alle anderen
  # sind sofort veröffentlicht. Caller, die explizit einen Wert setzen,
  # haben Vorrang — der Callback kickt nur, wenn published_at nil ist.
  def default_published_at
    return if published_at.present?
    self.published_at = Time.current unless assignee.is_a?(AgentActor)
  end

  # Eine Task darf nicht zur Subtask ihres eigenen Nachkommen werden
  # (würde Zyklus erzeugen). Der gleiche Check fängt auch self-parent.
  def parent_not_in_own_subtree
    return unless parent_id
    return errors.add(:parent_id, "kann nicht Eltern-Aufgabe von sich selbst sein") if parent_id == id

    current_id = parent_id
    seen = Set.new
    while current_id && !seen.include?(current_id)
      if current_id == id
        errors.add(:parent_id, "ergäbe einen Zyklus im Baum")
        return
      end
      seen << current_id
      current_id = Task.where(id: current_id).pick(:parent_id)
    end
  end

  # Audit-Logs leben jetzt im Auditable-Concern (#203 Phase E.5).

  def clear_next_step_if_done
    return unless saved_change_to_status? && done?
    task_topics.where(next_step: true).update_all(next_step: false)
  end
end
