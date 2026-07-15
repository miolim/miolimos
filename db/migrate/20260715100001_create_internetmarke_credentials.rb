# #995 (Hans): Portokassen-/API-Zugangsdaten für die Deutsche-Post-
# Internetmarke — pro Nutzer hinterlegbar (Einstellungen), Secrets
# verschlüsselt via Lockbox (analog OauthCredential).
class CreateInternetmarkeCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :internetmarke_credentials do |t|
      t.references :actor, null: false, foreign_key: true, index: { unique: true }
      t.string :portokasse_email, null: false
      t.string :portokasse_password_ciphertext, null: false
      t.string :client_id, null: false
      t.string :client_secret_ciphertext, null: false
      t.timestamps
    end
  end
end
