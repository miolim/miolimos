class AddLastSeenAtToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :last_seen_at, :datetime
  end
end
