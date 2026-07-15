# #995: die Frankierung eines druckbaren Dokuments (Document/Invoice).
# Echte Marke: einmaliger Matrixcode-PNG der Post (pro Sendung gekauft,
# Wiederverwendung unzulässig). Dummy: generiertes SVG-Muster zum Testen
# von Layout/Fensterposition — deutlich als MUSTER gekennzeichnet.
class PostageVoucher < ApplicationRecord
  belongs_to :printable, polymorphic: true
  belongs_to :creator, class_name: "Actor", optional: true

  validates :product_code, :product_label, :price_cents, :image, presence: true
  validates :voucher_id, presence: true, unless: :dummy?

  def price_euro = format("%.2f €", price_cents / 100.0).tr(".", ",")
end
