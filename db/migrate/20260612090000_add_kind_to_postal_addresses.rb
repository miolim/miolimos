# #622 (Hans): Adresstyp — größere Organisationen haben neben der
# Liegenschafts- eine Postadresse (oft Postfach); Briefe gehen an die
# Postadresse. kind=post markiert die Versandanschrift.
class AddKindToPostalAddresses < ActiveRecord::Migration[8.0]
  def change
    add_column :postal_addresses, :kind, :integer, default: 0, null: false
  end
end
