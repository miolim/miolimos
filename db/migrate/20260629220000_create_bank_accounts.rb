# #786 (Hans): Bankverbindungen an Person-/Org-KIs (mehrere möglich) — analog
# zu PostalAddress (#532). Quelle für u.a. das SEPA-Lastschriftmandat (Schuldner-
# Konto) und künftig Überweisungen.
class CreateBankAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_accounts do |t|
      t.string  :knowledge_item_uuid, null: false
      t.string  :iban
      t.string  :bic
      t.string  :bank_name
      t.string  :holder
      t.string  :label
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :bank_accounts, :knowledge_item_uuid
  end
end
