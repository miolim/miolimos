class HumanActor < Actor
  has_secure_password validations: false

  validates :email,    presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, if: -> { password.present? }
end
