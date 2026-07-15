# #995 (Hans): gekaufte (oder Dummy-)Internetmarke eines druckbaren
# Dokuments — das Markenbild wandert ins DIN-Anschriftfeld (Sichtfenster),
# damit der Brief ohne gesonderte Frankierung eingeworfen werden kann.
class CreatePostageVouchers < ActiveRecord::Migration[8.1]
  def change
    create_table :postage_vouchers do |t|
      t.references :printable, polymorphic: true, null: false,
                   index: { unique: true, name: "index_postage_vouchers_on_printable" }
      t.string  :voucher_id                       # Post-Marken-ID; NULL bei Dummy
      t.integer :product_code, null: false
      t.string  :product_label, null: false
      t.integer :price_cents, null: false
      t.boolean :dummy, null: false, default: false
      t.text    :image, null: false               # Data-URI (PNG echt / SVG-Muster)
      t.integer :wallet_balance_cents             # Portokassen-Rest nach Kauf (Info)
      t.references :creator, foreign_key: { to_table: :actors }
      t.timestamps
    end
  end
end
