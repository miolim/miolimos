# #532 (Hans, 2026-06-08): strukturierte Postadresse am Person/Org-KI —
# EN16931-tauglich (Zeile1/2, PLZ, Ort, Land) und sauber fürs DIN-Adressfeld.
# DB ist Source of Truth (keine Frontmatter-Sync). Bestehende einzeilige
# Adress-ContactPoints werden NICHT kopiert — der Renderer fällt darauf zurück,
# bis eine strukturierte Adresse erfasst ist (keine Doppel-Anzeige).
class CreatePostalAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :postal_addresses do |t|
      t.string  :knowledge_item_uuid, null: false
      t.string  :line1                              # Straße + Hausnr.
      t.string  :line2                              # Zusatz / c-o (optional)
      t.string  :postal_code                        # PLZ
      t.string  :city                               # Ort
      t.string  :country                            # Land
      t.boolean :billing,  null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :postal_addresses, :knowledge_item_uuid
  end
end
