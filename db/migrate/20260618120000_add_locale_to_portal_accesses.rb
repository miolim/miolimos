# #619 Stufe 3: Sprache je Portal-Zugang (DE/EN). nil = Default-Locale.
class AddLocaleToPortalAccesses < ActiveRecord::Migration[8.1]
  def change
    add_column :portal_accesses, :locale, :string
  end
end
