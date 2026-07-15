# #995: Zugangsdaten für die Internetmarke-REST-API (developer.dhl.com) —
# App-Credentials (Client-ID/-Secret) + Portokassen-Login, pro Nutzer.
# Secrets verschlüsselt (Lockbox), analog OauthCredential.
class InternetmarkeCredential < ApplicationRecord
  belongs_to :actor

  has_encrypted :portokasse_password
  has_encrypted :client_secret

  validates :actor_id, uniqueness: true
  validates :portokasse_email, :portokasse_password, :client_id, :client_secret,
            presence: true
end
