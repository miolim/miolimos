class AddInboxRunRequestedAtToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :inbox_run_requested_at, :datetime
  end
end
