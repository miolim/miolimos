require "test_helper"

# #1171 (aus immoOS #1170): der gemeinsame Betrags-Parser — ein Regelwerk
# für GiroCode-Betrag, Rechnungszeilen und Printable-Beträge.
class DezimalbetragTest < ActiveSupport::TestCase
  test "deutsches Format: Tausenderpunkt + Komma" do
    assert_equal 1234.56.to_d, Dezimalbetrag.parse("1.234,56")
    assert_equal 700.5.to_d, Dezimalbetrag.parse("700,50")
  end

  test "englisches Format: Punkt als Dezimaltrenner" do
    assert_equal 1234.56.to_d, Dezimalbetrag.parse("1234.56")
    assert_equal 12.5.to_d, Dezimalbetrag.parse("12.5")
  end

  test "reine Tausender-Gruppierung ohne Komma bleibt Tausenderpunkt" do
    assert_equal 1234.to_d, Dezimalbetrag.parse("1.234")
    assert_equal 1_234_567.to_d, Dezimalbetrag.parse("1.234.567")
  end

  test "Ganzzahl und negative Beträge" do
    assert_equal 700.to_d, Dezimalbetrag.parse("700")
    assert_equal(-12.5.to_d, Dezimalbetrag.parse("-12,50"))
  end

  test "Währungszeichen und Beiwerk werden abgestreift" do
    assert_equal 1234.56.to_d, Dezimalbetrag.parse("1.234,56 €")
    assert_equal 1234.56.to_d, Dezimalbetrag.parse("EUR 1.234,56")
  end

  test "leer und Müll ergeben nil" do
    assert_nil Dezimalbetrag.parse(nil)
    assert_nil Dezimalbetrag.parse("")
    assert_nil Dezimalbetrag.parse("   ")
    assert_nil Dezimalbetrag.parse("-")
    assert_nil Dezimalbetrag.parse("abc")
  end
end
