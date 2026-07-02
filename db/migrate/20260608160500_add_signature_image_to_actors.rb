# #547 (Hans, 2026-06-08): Unterschriftsbild des Users (Data-URI). Wird beim
# signierten Dokument ins Unterschriftsfeld gesetzt. Klein + selbst-enthalten,
# damit der Chrome-PDF-Render es ohne Asset-Server einbetten kann.
class AddSignatureImageToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :signature_image, :text
  end
end
