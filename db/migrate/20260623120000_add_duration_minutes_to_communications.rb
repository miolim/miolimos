# #765 (Hans, 2026-06-23): Dauer (Minuten) für dokumentierte Anrufe (Call-STI).
# Nur bei Anrufen gesetzt; bei Mails/Portalnachrichten NULL.
class AddDurationMinutesToCommunications < ActiveRecord::Migration[8.1]
  def change
    add_column :communications, :duration_minutes, :integer
  end
end
