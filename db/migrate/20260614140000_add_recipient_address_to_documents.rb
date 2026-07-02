# #694 (Hans): Pro Dokument wählbare Empfänger-Postadresse — nötig, wenn
# der Empfänger (z.B. eine Krankenkasse) mehrere Postadressen hat.
# nil = automatisch (mailing_address). FK auf postal_addresses (bigint).
class AddRecipientAddressToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :recipient_address_id, :bigint, null: true
  end
end
