require "test_helper"

# #995: Frankierung eines druckbaren Dokuments.
class PostageVoucherTest < ActiveSupport::TestCase
  def build_voucher(**attrs)
    doc = Document.create!(kind: :brief)
    doc.build_postage_voucher({ product_code: 1, product_label: "Standardbrief",
                                price_cents: 95, dummy: true,
                                image: "data:image/svg+xml;base64,AA==" }.merge(attrs))
  end

  # #1675: umgedreht. Die Pflicht auf voucher_id schlug NACH dem Kauf fehl, wenn
  # die Post die Antwort ohne Marken-ID lieferte — die bezahlte Marke ging
  # verloren, und der nächste Klick kaufte noch einmal. Das Bild ist die Marke.
  test "eine bezahlte Marke ist auch ohne voucher_id gueltig — das Bild ist Pflicht" do
    assert build_voucher.valid?
    assert build_voucher(dummy: false).valid?
    assert build_voucher(dummy: false, voucher_id: "A0123456789").valid?
    refute build_voucher(dummy: false, image: nil).valid?
  end

  test "eine Frankierung pro Dokument — Neufrankieren ersetzt" do
    doc = Document.create!(kind: :brief)
    doc.create_postage_voucher!(product_code: 1, product_label: "Standardbrief",
                                price_cents: 95, dummy: true, image: "data:x")
    assert_raises(ActiveRecord::RecordNotUnique) do
      PostageVoucher.create!(printable: doc, product_code: 11, product_label: "Kompaktbrief",
                             price_cents: 110, dummy: true, image: "data:y")
    end
  end

  test "price_euro formatiert deutsch" do
    assert_equal "0,95 €", build_voucher.price_euro
  end
end
