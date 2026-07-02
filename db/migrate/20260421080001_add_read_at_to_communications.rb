class AddReadAtToCommunications < ActiveRecord::Migration[8.1]
  def change
    add_column :communications, :read_at, :datetime
    # Für den "Ungelesen"-Zähler auf Topics und im Dashboard.
    add_index  :communications, :read_at
  end
end
