class TaskTemplate < ApplicationRecord
  belongs_to :agent_actor, class_name: "Actor", optional: true

  validates :title, presence: true

  # Picker-Suggest-Scope: per Suchstring filtern + optional einen
  # Default-Agent priorisieren (Treffer fuer diesen Agent kommen zuerst,
  # globale Vorlagen danach, Treffer fuer andere Agents zuletzt).
  scope :search, ->(q) {
    pattern = "%#{q.to_s.strip}%"
    where("title ILIKE ? OR description ILIKE ?", pattern, pattern)
  }

  # Beim Quickadd: bevorzugt Templates ohne Agent (globale) +
  # Templates fuer den angegebenen Agent.
  scope :for_agent, ->(agent_id) {
    if agent_id.present?
      where("agent_actor_id IS NULL OR agent_actor_id = ?", agent_id)
        .order(Arel.sql("agent_actor_id IS NULL")) # FALSE first → Agent-Match zuerst
        .order(:title)
    else
      order(:title)
    end
  }
end
