class AgentActor < Actor
  before_validation :ensure_api_token

  validates :api_token_digest, presence: true, uniqueness: true
  validates :description, presence: true

  # #1052: In der DB liegt nur noch der SHA256-Digest. Der Klartext ist
  # TRANSIENT — `api_token` liefert ihn ausschließlich direkt nach dem
  # Generieren/Setzen in derselben Objekt-Instanz (Anlegen, Rotation);
  # nach einem Reload gibt es ihn nirgendwo mehr. UI zeigt ihn deshalb
  # einmalig via Flash, danach hilft nur Rotieren.
  def api_token
    @api_token_plaintext
  end

  def api_token=(value)
    @api_token_plaintext  = value.presence
    self.api_token_digest = value.present? ? Actor.digest_api_token(value) : nil
  end

  # #152: Resource-Typen, die ein frisch onboardeter Agent standardmäßig
  # bedienen darf. Delete wird separat aufs Wishlist-Niveau gegated —
  # siehe `grant_default_capabilities!(include_delete:)`.
  DEFAULT_RESOURCE_TYPES = %w[
    Task KnowledgeItem Source Topic Communication Awaiting InboxItem
  ].freeze

  # #1052: gibt den neuen KLARTEXT zurück (Einmalanzeige im UI) —
  # gespeichert wird nur der Digest.
  def regenerate_api_token!
    update!(api_token: self.class.generate_api_token)
    api_token
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
    self.api_token = self.class.generate_api_token if api_token_digest.blank?
  end
end
