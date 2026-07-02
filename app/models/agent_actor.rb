class AgentActor < Actor
  before_validation :ensure_api_token

  validates :api_token, presence: true, uniqueness: true
  validates :description, presence: true

  # #152: Resource-Typen, die ein frisch onboardeter Agent standardmäßig
  # bedienen darf. Delete wird separat aufs Wishlist-Niveau gegated —
  # siehe `grant_default_capabilities!(include_delete:)`.
  DEFAULT_RESOURCE_TYPES = %w[
    Task KnowledgeItem Source Topic Communication Awaiting InboxItem
  ].freeze

  def regenerate_api_token!
    update!(api_token: self.class.generate_api_token)
  end

  def self.generate_api_token
    SecureRandom.hex(32)
  end

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

  private

  def ensure_api_token
    self.api_token ||= self.class.generate_api_token
  end
end
