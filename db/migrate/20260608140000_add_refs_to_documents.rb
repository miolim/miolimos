# #532 (Hans, 2026-06-08): Geschäftszeichen am Dokument — Ihr Zeichen /
# Unser Zeichen (DIN-5008-Informationsblock).
class AddRefsToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :your_ref, :string   # Ihr Zeichen
    add_column :documents, :our_ref,  :string   # Unser Zeichen
  end
end
