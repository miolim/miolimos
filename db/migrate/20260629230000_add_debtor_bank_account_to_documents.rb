# #786 Inkrement 2 (Hans): Für das SEPA-Lastschriftmandat die gewählte
# Bankverbindung des Schuldners (= Aussteller) am Dokument festhalten —
# analog zur gewählten Empfänger-Postadresse (#694). nil = automatisch
# (erste Bankverbindung des Ausstellers).
class AddDebtorBankAccountToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :debtor_bank_account_id, :bigint
  end
end
