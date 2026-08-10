require "test_helper"

# #1337 Schnitt 2: der offene-Posten-Ausgleich. Geprüft wird das, was im
# immoOS-Fork im Betrieb schiefgegangen ist — Vorzeichen, Teilzahlung,
# Sammelüberweisung und die doppelte Vergabe eines Umsatzes.
class ObligationSettlementTest < ActiveSupport::TestCase
  setup do
    @konto = BankLedger.create!(label: "Geschäftskonto")
  end

  def beleg(brutto: 100, richtung: :eingehend)
    inv = Invoice.create!(kind: :rechnung, direction: richtung)
    inv.invoice_lines.create!(description: "X", quantity: 1, unit_price: brutto, tax_rate: 0, position: 0)
    inv.reload
  end

  def pflicht(inv, betrag: nil, faellig: nil)
    inv.payment_obligations.create!(amount: betrag || (inv.gross_total * inv.obligation_sign),
                                    due_on: faellig, announced_by: inv)
  end

  def umsatz(betrag, **attrs)
    @konto.bank_transactions.create!({ booked_on: Date.new(2026, 4, 1), amount: betrag }.merge(attrs))
  end

  test "eine Auszahlung tilgt eine Zahlungspflicht vollständig" do
    inv = beleg(brutto: 100)
    o   = pflicht(inv)
    tx  = umsatz(-100, purpose: "Handwerker")

    assert Bank::ObligationMatch.assign(tx, o)
    assert_equal BigDecimal("-100"), o.reload.settled_amount, "nachgeführt, nicht gesetzt"
    assert_equal :bezahlt, o.state
    assert_equal "bezahlt", inv.reload.payment_status
    assert_equal BigDecimal("0"), tx.reload.restbetrag
    assert_not_includes BankTransaction.unentschieden, tx
  end

  # #1322 im Fork: Ein Umsatz galt nach der ERSTEN Zuordnung als erledigt — die
  # zweite Rechnung kam nie an ihn heran.
  test "eine Sammelüberweisung tilgt mehrere Pflichten" do
    a = pflicht(beleg(brutto: 900), betrag: -900)
    b = pflicht(beleg(brutto: 550), betrag: -550)
    tx = umsatz(-1450.21, purpose: "Sammelüberweisung Glaserei")

    assert Bank::ObligationMatch.assign(tx, a)
    assert_includes BankTransaction.unentschieden, tx.reload,
                    "nicht erledigt, solange er nicht ausgeschöpft ist"
    assert Bank::ObligationMatch.assign(tx, b)

    assert_equal BigDecimal("1450"), tx.reload.zugeordneter_betrag
    assert_equal BigDecimal("0.21"), tx.restbetrag
    assert_equal :bezahlt, a.reload.state
    assert_equal :bezahlt, b.reload.state
  end

  test "Teilzahlung lässt die Pflicht teilweise getilgt zurück" do
    o  = pflicht(beleg(brutto: 100))
    tx = umsatz(-40)

    Bank::ObligationMatch.assign(tx, o)
    assert_equal :teilweise, o.reload.state
    assert_equal BigDecimal("-60"), o.open_amount
    assert_equal "offen", o.bearer.reload.payment_status
  end

  # Ohne Angabe wird der KLEINERE der beiden Reste zugeordnet — mehr wäre eine
  # Behauptung über Geld, das nie geflossen ist.
  test "ein großer Umsatz tilgt eine kleine Pflicht nur in ihrer Höhe" do
    o  = pflicht(beleg(brutto: 100))
    tx = umsatz(-500)

    Bank::ObligationMatch.assign(tx, o)
    assert_equal BigDecimal("-100"), o.reload.settled_amount
    assert_equal BigDecimal("400"),  tx.reload.restbetrag
  end

  # Der Fehler aus #1329: Eine Gutschrift ist negativ und wird durch eine
  # Erstattung getilgt, die ebenfalls in die andere Richtung läuft.
  test "eine erstattete Gutschrift gilt als getilgt" do
    inv = beleg(brutto: 175.08)
    gut = pflicht(inv, betrag: 175.08)          # Guthaben: fließt UNS zu
    ein = umsatz(175.08, purpose: "Erstattung") # Einzahlung

    assert Bank::ObligationMatch.assign(ein, gut)
    assert_equal :bezahlt, gut.reload.state
    assert_equal "bezahlt", inv.reload.payment_status
  end

  test "eine Tilgung muss dieselbe Geldrichtung haben wie der Umsatz" do
    o  = pflicht(beleg(brutto: 100))            # −100
    ein = umsatz(100, purpose: "Eingang")       # +100

    s = ObligationSettlement.new(payment_obligation: o, bank_transaction: ein, amount: -100)
    assert_not s.valid?
    assert_includes s.errors.attribute_names, :amount
  end

  # Die Prüfung gehört in den Dienst UND ins Modell — im Fork stand sie nur in
  # der Auswahlliste, und über den Dienst ließ sich doppelt vergeben.
  test "ein Umsatz kann nicht über seinen Betrag hinaus vergeben werden" do
    a  = pflicht(beleg(brutto: 100))
    b  = pflicht(beleg(brutto: 100))
    tx = umsatz(-100)

    Bank::ObligationMatch.assign(tx, a)
    assert_not Bank::ObligationMatch.assign(tx, b), "nichts mehr übrig"

    direkt = ObligationSettlement.new(payment_obligation: b, bank_transaction: tx, amount: -100)
    assert_not direkt.valid?, "auch am Modell vorbei nicht"
  end

  test "derselbe Umsatz tilgt dieselbe Pflicht nur einmal" do
    o  = pflicht(beleg(brutto: 100))
    tx = umsatz(-500)
    assert     Bank::ObligationMatch.assign(tx, o, 40)
    assert_not Bank::ObligationMatch.assign(tx, o, 20), "Teilbeträge gehören in EINE Zeile"
  end

  test "Zuordnung lösen setzt den Zahlstatus zurück" do
    inv = beleg(brutto: 100)
    o   = pflicht(inv)
    tx  = umsatz(-100)
    Bank::ObligationMatch.assign(tx, o)
    assert_equal "bezahlt", inv.reload.payment_status

    Bank::ObligationMatch.unassign(tx)
    assert_equal BigDecimal("0"), o.reload.settled_amount
    assert_equal "offen", inv.reload.payment_status
  end

  # Ein gelöschter Umsatz darf keinen Zahlstatus von vorher zurücklassen.
  test "wird der Umsatz gelöscht, bewerten sich die Pflichten neu" do
    inv = beleg(brutto: 100)
    o   = pflicht(inv)
    tx  = umsatz(-100)
    Bank::ObligationMatch.assign(tx, o)

    tx.destroy!
    assert_equal BigDecimal("0"), o.reload.settled_amount
    assert_equal "offen", inv.reload.payment_status
  end

  test "Ausbuchung tilgt den Rest ohne Umsatz" do
    inv = beleg(brutto: 100)
    o   = pflicht(inv)
    Bank::ObligationMatch.assign(umsatz(-90), o)
    assert_equal :teilweise, o.reload.state

    assert Bank::ObligationMatch.write_off(o, note: "Skonto", on: Date.new(2026, 5, 1))
    assert_equal :bezahlt, o.reload.state
    assert_equal "bezahlt", inv.reload.payment_status
    assert_not Bank::ObligationMatch.write_off(o), "nichts mehr offen"
  end

  # Das Häkchen an der Card schreibt nicht mehr direkt in die Ableitungsspalte.
  test "von Hand getilgt läuft über dieselbe Tabelle und lässt Bank-Tilgungen stehen" do
    o = pflicht(beleg(brutto: 100))
    Bank::ObligationMatch.assign(umsatz(-30), o)

    o.reload.settle_fully!
    assert_equal :bezahlt, o.reload.state
    assert_equal %w[zahlung manuell].sort, o.obligation_settlements.map(&:kind).sort

    o.unsettle!
    assert_equal BigDecimal("-30"), o.reload.settled_amount, "die Bankzahlung bleibt"
    assert_equal :teilweise, o.state
  end

  test "Überzahlung ist erkennbar" do
    o = pflicht(beleg(brutto: 100))
    Bank::ObligationMatch.assign(umsatz(-100), o)
    ObligationSettlement.create!(payment_obligation: o, kind: :manuell, amount: -20)
    assert_equal :ueberzahlt, o.reload.state
  end
end
