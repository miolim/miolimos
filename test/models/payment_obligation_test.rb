require "test_helper"

# #1336 Stufe 2: die Zahlungspflicht. Geprüft wird vor allem das, woran der
# Fork nachweislich gescheitert ist — Vorzeichen, Teiltilgung, und der Beleg
# ganz ohne Pflicht.
class PaymentObligationTest < ActiveSupport::TestCase
  def eingangsbeleg(brutto: 100)
    inv = Invoice.create!(kind: :rechnung, direction: :eingehend)
    inv.invoice_lines.create!(description: "X", quantity: 1, unit_price: brutto, tax_rate: 0, position: 0)
    inv.reload
  end

  # Der eigentliche Gewinn: Ein Beleg ohne Zahlungspflicht ist kein offener
  # Posten — und zwar ohne dass jemand eine Regel befolgen muss.
  test "Beleg ohne Zahlungspflicht hat keinen Zahlstatus und ist nicht überfällig" do
    inv = Invoice.create!(kind: :rechnung, direction: :eingehend, document_type: :bescheid)
    assert_empty inv.payment_obligations
    assert_nil   inv.payment_status, "kein Zahlstatus ohne Zahlungspflicht"
    assert_nil   inv.next_due_on
    assert_not   inv.overdue?
    assert_not   Invoice.offen.exists?(id: inv.id), "darf nicht als offener Posten filterbar sein"
  end

  # Der Fall, an dem die alte Fälligkeitsspalte zerbrach.
  test "ein Beleg trägt mehrere Fälligkeiten, nächste Fälligkeit ist die früheste offene" do
    inv = eingangsbeleg(brutto: 400)
    q1 = inv.payment_obligations.create!(amount: -100, due_on: Date.new(2026, 2, 15), label: "Rate 1 von 4")
    inv.payment_obligations.create!(amount: -100, due_on: Date.new(2026, 5, 15), label: "Rate 2 von 4")
    inv.payment_obligations.create!(amount: -100, due_on: Date.new(2026, 8, 15), label: "Rate 3 von 4")

    assert_equal Date.new(2026, 2, 15), inv.next_due_on
    q1.settle_fully!
    assert_equal Date.new(2026, 5, 15), inv.reload.next_due_on, "getilgte Raten zählen nicht mehr"
  end

  # Hans' Präzisierung: Vorzeichen = Geldrichtung aus eigener Sicht. Damit hat
  # die Pflicht dasselbe Vorzeichen wie der Umsatz, der sie später tilgt.
  test "Vorzeichen kommt aus der Geldrichtung des Belegs" do
    assert_equal(-1, Invoice.new(direction: :eingehend).obligation_sign)
    assert_equal 1,  Invoice.new(direction: :ausgehend).obligation_sign
  end

  # #1329 im Fork: Eine vollständig erstattete Gutschrift galt als unbezahlt,
  # weil die Prüfung still einen positiven Betrag voraussetzte.
  test "Zahlstatus ist vorzeichenrichtig — eine erstattete Gutschrift gilt als getilgt" do
    inv  = eingangsbeleg
    gut  = inv.payment_obligations.create!(amount: 175.08)   # Guthaben: fließt UNS zu
    assert_equal :offen, gut.state

    gut.update!(settled_amount: 175.08)
    assert_equal :bezahlt, gut.state
    assert gut.settled?
    assert_equal "bezahlt", inv.reload.payment_status
  end

  test "Teiltilgung und Überzahlung sind unterscheidbar" do
    inv = eingangsbeleg(brutto: 100)
    o   = inv.payment_obligations.create!(amount: -100)

    o.update!(settled_amount: -40)
    assert_equal :teilweise, o.state
    assert_equal(-60, o.open_amount)
    assert_equal "offen", inv.reload.payment_status

    o.update!(settled_amount: -120)
    assert_equal :ueberzahlt, o.state
  end

  test "überfällig ist eine Aussage über die Zahlungspflicht, nicht über den Beleg" do
    inv = eingangsbeleg
    o   = inv.payment_obligations.create!(amount: -100, due_on: Date.current - 3)
    assert o.overdue?
    assert inv.overdue?

    o.settle_fully!
    assert_not inv.reload.overdue?, "getilgt ist nicht überfällig"
  end

  # Hans' Antwort 4: nicht woher sie kommt, sondern WEM sie gehört. Eine
  # Pflicht, die ein Beleg nur ankündigt, gehört nicht zu seinem Zahlstatus.
  test "angekündigte, aber fremd getragene Pflicht zählt nicht zum Zahlstatus des Belegs" do
    bescheid = Invoice.create!(kind: :rechnung, direction: :eingehend, document_type: :bescheid)
    traeger  = eingangsbeleg
    o = PaymentObligation.create!(bearer: traeger, announced_by: bescheid,
                                  amount: -909, due_on: Date.current - 30)

    assert_includes bescheid.announced_payment_obligations, o
    assert_empty    bescheid.payment_obligations
    assert_nil      bescheid.reload.payment_status, "der Bescheid trägt sie nicht — also mahnt er nicht"
    assert_not      bescheid.overdue?
    assert          traeger.reload.overdue?, "der Träger führt sie"
  end

  test "der Zahlstatus wird nachgeführt, nicht gesetzt" do
    inv = eingangsbeleg
    o   = inv.payment_obligations.create!(amount: -100)
    assert_equal "offen", inv.reload.payment_status

    o.settle_fully!
    assert_equal "bezahlt", inv.reload.payment_status

    o.destroy!
    assert_nil inv.reload.payment_status, "letzte Pflicht weg = kein Zahlstatus mehr"
  end
end
