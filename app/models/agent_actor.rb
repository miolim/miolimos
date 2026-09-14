class AgentActor < Actor
  # #1499: benannte Token mit Ablauf, Benutzungsspur und eigenem Rueckzug.
  # Das fruehere Einzel-Token an der Actor-Spalte (#1052) ist seit der
  # Rotation am 14.09.2026 entfallen — Zugang gibt es nur noch ueber
  # api_tokens. Der Klartext eines Tokens existiert ausschliesslich im
  # Augenblick des Erzeugens (ApiToken.issue!).
  has_many :api_tokens, foreign_key: :actor_id, dependent: :destroy, inverse_of: :actor

  validates :description, presence: true

  # #152: Resource-Typen, die ein frisch onboardeter Agent standardmäßig
  # bedienen darf. Delete wird separat aufs Wishlist-Niveau gegated —
  # siehe `grant_default_capabilities!(include_delete:)`.
  DEFAULT_RESOURCE_TYPES = %w[
    Task KnowledgeItem Source Topic Communication Awaiting InboxItem
  ].freeze

  # #152: Standardrechte für einen frisch angelegten Agent. Idempotent —
  # mehrfaches Aufrufen schadet nicht.
  def grant_default_capabilities!(include_delete: false)
    actions = %w[read create update]
    actions << "delete" if include_delete
    DEFAULT_RESOURCE_TYPES.each do |type|
      cap = capabilities.find_or_initialize_by(resource_type: type, effect: :allow)
      cap.actions = actions
      cap.save!
    end
  end
end
