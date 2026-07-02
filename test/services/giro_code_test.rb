require "test_helper"

# #625 (Hans): EPC-QR / GiroCode-Payload (EPC069-12).
class GiroCodeTest < ActiveSupport::TestCase
  test "payload baut das EPC069-12-Format mit Betrag" do
    p = GiroCode.payload(name: "miolim UG", iban: "DE89 3704 0044 0532 0130 00",
                         amount: 1234.5, remittance: "Rechnung 2026-001", bic: "COBADEFFXXX")
    lines = p.split("\n")
    assert_equal "BCD", lines[0]
    assert_equal "002", lines[1]
    assert_equal "1",   lines[2]
    assert_equal "SCT", lines[3]
    assert_equal "COBADEFFXXX", lines[4]
    assert_equal "miolim UG",   lines[5]
    assert_equal "DE89370400440532013000", lines[6]   # Leerzeichen raus, upcase
    assert_equal "EUR1234.50", lines[7]                # Punkt-Dezimal, 2 Stellen
    assert_equal "Rechnung 2026-001", lines[10]
  end

  test "payload ohne Betrag lässt das Betragsfeld leer" do
    p = GiroCode.payload(name: "X", iban: "DE89370400440532013000")
    assert_equal "", p.split("\n", -1)[7]   # -1: trailing-Leerfelder behalten
  end

  test "payload verlangt IBAN und Namen" do
    assert_raises(GiroCode::Error) { GiroCode.payload(name: "X", iban: "") }
    assert_raises(GiroCode::Error) { GiroCode.payload(name: "", iban: "DE89370400440532013000") }
  end

  test "payload lehnt unplausible Beträge ab" do
    assert_raises(GiroCode::Error) { GiroCode.payload(name: "X", iban: "DE89370400440532013000", amount: 10_000_000_000) }
  end

  test "svg liefert ein Inline-SVG" do
    svg = GiroCode.svg(name: "miolim UG", iban: "DE89370400440532013000", amount: 10.0)
    assert_includes svg, "<svg"
    assert_includes svg, "</svg>"
  end
end
