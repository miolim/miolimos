class OauthCredential < ApplicationRecord
  belongs_to :actor

  has_many :communications, dependent: :nullify

  has_encrypted :access_token
  has_encrypted :refresh_token

  validates :provider,       presence: true
  validates :email_address,  presence: true, uniqueness: true

  scope :active,     -> { where(active: true) }
  scope :for_email,  ->(email) { where(email_address: email) }

  def expired?(buffer: 60.seconds)
    expires_at.present? && expires_at <= Time.current + buffer
  end
end
