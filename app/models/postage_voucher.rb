# #995: die Frankierung eines druckbaren Dokuments (Document/Invoice).
# Echte Marke: einmaliger Matrixcode-PNG der Post (pro Sendung gekauft,
# Wiederverwendung unzulässig). Dummy: generiertes SVG-Muster zum Testen
# von Layout/Fensterposition — deutlich als MUSTER gekennzeichnet.
class PostageVoucher < ApplicationRecord
  belongs_to :printable, polymorphic: true
  belongs_to :creator, class_name: "Actor", optional: true

  validates :product_code, :product_label, :price_cents, :image, presence: true
  # #1675: KEINE Pflicht mehr auf voucher_id. Liefert die Post die Antwort ohne
  # Marken-ID, ist die Marke trotzdem bezahlt und das Bild da — die Validierung
  # schlug dann NACH dem Kauf fehl: Bild verworfen, Fehlerseite, und der nächste
  # Klick kaufte noch einmal. Die ID ist Beiwerk (Anzeige/Reklamation), das Bild
  # ist die Marke.

  def price_euro = format("%.2f €", price_cents / 100.0).tr(".", ",")
end
