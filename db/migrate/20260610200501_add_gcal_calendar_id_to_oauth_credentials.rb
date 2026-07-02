class AddGcalCalendarIdToOauthCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_credentials, :gcal_calendar_id, :string
  end
end
