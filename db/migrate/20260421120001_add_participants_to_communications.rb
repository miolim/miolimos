class AddParticipantsToCommunications < ActiveRecord::Migration[8.1]
  # Speichert beim Gmail-Sync die geparsten E-Mail-Adressen je Rolle:
  #   { "sender" => ["a@b.de"], "recipient" => [...], "cc" => [...], "bcc" => [...] }
  # Wird im Detail-View zusammen mit den verlinkten Contacts angezeigt;
  # Adressen ohne Contact kriegen einen "+ Kontakt anlegen"-Link.
  def change
    add_column :communications, :participants, :jsonb, default: {}, null: false
  end
end
