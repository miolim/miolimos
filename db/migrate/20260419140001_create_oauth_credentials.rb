class CreateOauthCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_credentials do |t|
      t.references :actor, null: false, foreign_key: true
      t.string :provider, null: false, default: "google"

      # Lockbox-encrypted — stored as text ciphertext columns
      t.text :access_token_ciphertext
      t.text :refresh_token_ciphertext

      t.datetime :expires_at
      t.jsonb :scopes, null: false, default: []

      t.string :email_address, null: false
      t.string :label

      t.string :last_history_id
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :oauth_credentials, :email_address, unique: true
    add_index :oauth_credentials, :provider
    add_index :oauth_credentials, :active
  end
end
