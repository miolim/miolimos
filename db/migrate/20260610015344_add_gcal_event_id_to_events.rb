class AddGcalEventIdToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :gcal_event_id, :string
  end
end
