class AddSyncSinceToOauthCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_credentials, :sync_since, :datetime
  end
end
