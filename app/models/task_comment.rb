# Kommentar-Thread an einem Task. Generisch für alle Actors —
# HumanActor (Hans) und AgentActors (z.B. miolim_builder) nutzen
# denselben Mechanismus, um asynchron Klärungen, Annahmen und
# Status-Updates am Task festzuhalten.
class TaskComment < ApplicationRecord
  belongs_to :task, touch: true
  belongs_to :actor
  has_many :comment_reads, dependent: :destroy

  validates :body, presence: true

  scope :ordered,   -> { order(created_at: :asc) }
  # #167: Soft-Publish. published_at IS NULL = Entwurf. Nur Autor
  # darf Drafts sehen; Agent-API liefert nur Published aus.
  scope :published, -> { where.not(published_at: nil) }
  scope :drafts,    -> { where(published_at: nil) }

  def draft?
    published_at.nil?
  end

  def publish!
    update!(published_at: Time.current) if draft?
  end

  # Sichtbarkeit: Published für alle, Drafts nur für den Autor.
  def visible_to?(actor)
    !draft? || actor_id == actor&.id
  end

  # #113: nur den letzten eigenen Comment darf der jeweilige Actor
  # nachträglich bearbeiten oder löschen. Damit Hans (oder ich) eine
  # frische Antwort korrigieren können, ohne Diskussions-Historie
  # rückwirkend zu verändern.
  # #181: Entwürfe darf der Autor IMMER bearbeiten/löschen — die
  # sind nicht Teil des Diskurses (Assignee sieht sie nicht), und es
  # wäre wenig hilfreich, wenn ein Entwurf nach einem späteren
  # veröffentlichten Comment „gefangen " ist.
  def editable_by?(actor)
    return false unless actor && actor_id == actor.id
    return true if draft?
    task.comments.published.maximum(:created_at) == created_at
  end

  # Comments, die `actor` noch nicht gelesen hat — und die nicht von
  # ihm selbst stammen (eigene Beiträge sind per Definition gelesen).
  scope :unread_for, ->(actor) {
    where.not(actor_id: actor.id)
      .where.not(id: CommentRead.where(actor_id: actor.id).select(:task_comment_id))
  }

  def read_by?(actor)
    comment_reads.exists?(actor_id: actor.id) || actor_id == actor.id
  end
end
