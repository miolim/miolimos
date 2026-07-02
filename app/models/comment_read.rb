# Markierung "Actor X hat TaskComment Y zu Zeitpunkt Z gelesen".
# Eindeutiger Index auf (actor_id, task_comment_id) erzwingt
# Idempotenz; das Modell speichert nur den ersten Read.
class CommentRead < ApplicationRecord
  belongs_to :actor
  belongs_to :task_comment

  validates :read_at, presence: true
end
