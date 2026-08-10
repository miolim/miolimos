require "test_helper"

# #1337 Schnitt 4: die automatische Zuordnung. Sie greift NUR bei eindeutigem,
# betragsexaktem Treffer — alles andere bleibt Handarbeit, weil eine falsch
# verrechnete Zahlung nicht auffällt.
#
# Der Kern dieses Tests ist der zweite Suchweg: Bei SEPA-Lastschriften steht im
# Auszug keine IBAN des Empfängers, sondern seine Gläubiger-ID. Wer nur über
# hinterlegte Bankverbindungen sucht, findet dort nie etwas.
class Bank::ObligationMatchAutoTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    @konto = BankLedger.create!(label: "Geschäftskonto")
  end

  def kreditor(titel)
    FileProxy.create(actor: @hans, item_type: :organization, title: titel, content: "").tap { |ki| ki.reload }
  end

  def eingangsbeleg(kreditor_uuid, brutto)
    inv = Invoice.create!(kind: :rechnung, direction: :eingehend, issuer_uuid: kreditor_uuid)
    inv.invoice_lines.create!(description: "Leistung", quantity: 1, unit_price: brutto,
                              tax_rate: 0, position: 0)
    inv.reload
    inv.payment_obligations.create!(amount: -brutto, due_on: Date.new(2026, 4, 15),
                                    announced_by: inv)
    inv
  end

  def umsatz(betrag, **attrs)
    @konto.bank_transactions.create!({ booked_on: Date.new(2026, 4, 10), amount: betrag }.merge(attrs))
  end

  # ── Weg 1: hinterlegte Bankverbindung ─────────────────────────────────

  test "eindeutiger betragsexakter Treffer über die Bankverbindung wird zugeordnet" do
    ki = kreditor("Elektro Meier GmbH")
    BankAccount.create!(knowledge_item_uuid: ki.uuid, iban: "DE02120300000000202051")
    beleg = eingangsbeleg(ki.uuid, 119)
    umsatz(-119, counterparty_iban: "DE02120300000000202051", purpose: "Rechnung 4711")

    assert_equal 1, Bank::ObligationMatch.auto(@konto)
    assert_equal "bezahlt", beleg.reload.payment_status
  end

  # ── Weg 2: die Gläubiger-ID ───────────────────────────────────────────

  # Der Fall, an dem die Suche allein über Bankverbindungen scheitert.
  test "SEPA-Lastschrift wird über die Gläubiger-ID des Kontakts gefunden" do
    ki = kreditor("Stadtwerke Beispielstadt")
    ki.identifiers.create!(label: "Gläubiger-Identifikationsnummer",
                           value: "DE98ZZZ09999999999", position: 0)
    beleg = eingangsbeleg(ki.uuid, 119)
    # Kein counterparty_iban — genau wie im echten Auszug bei einer Lastschrift.
    umsatz(-119, purpose: "Abschlag Strom Mandat M-42 DE98ZZZ09999999999")

    assert_equal 1, Bank::ObligationMatch.auto(@konto)
    assert_equal "bezahlt", beleg.reload.payment_status
  end

  test "eine zu kurze Kennnummer trifft nicht zufällig" do
    ki = kreditor("Klein GmbH")
    ki.identifiers.create!(label: "Gläubiger-Identifikationsnummer", value: "DE12", position: 0)
    eingangsbeleg(ki.uuid, 119)
    umsatz(-119, purpose: "Zahlung DE12345 Sammelposten")

    assert_equal 0, Bank::ObligationMatch.auto(@konto)
  end

  # ── Weg 3 und 4: verknüpfter Kontakt, exakter Name ────────────────────

  test "der am Umsatz verknüpfte Kontakt zählt" do
    ki = kreditor("Gerüstbau Nord")
    beleg = eingangsbeleg(ki.uuid, 250)
    umsatz(-250, counterparty_knowledge_item_uuid: ki.uuid)

    assert_equal 1, Bank::ObligationMatch.auto(@konto)
    assert_equal "bezahlt", beleg.reload.payment_status
  end

  test "der exakte Name des Zahlungsempfängers zählt" do
    ki = kreditor("Malerbetrieb Süd")
    beleg = eingangsbeleg(ki.uuid, 80)
    umsatz(-80, counterparty_name: "malerbetrieb süd")

    assert_equal 1, Bank::ObligationMatch.auto(@konto)
    assert_equal "bezahlt", beleg.reload.payment_status
  end

  # ── Wo die Automatik bewusst schweigt ─────────────────────────────────

  test "bei zwei gleich hohen offenen Pflichten desselben Kreditors wird nichts zugeordnet" do
    ki = kreditor("Doppelt GmbH")
    a = eingangsbeleg(ki.uuid, 119)
    b = eingangsbeleg(ki.uuid, 119)
    umsatz(-119, counterparty_knowledge_item_uuid: ki.uuid)

    assert_equal 0, Bank::ObligationMatch.auto(@konto), "mehrdeutig heißt: liegen lassen"
    assert_nil a.reload.payment_obligations.sole.settled_amount.nonzero?
    assert_nil b.reload.payment_obligations.sole.settled_amount.nonzero?
  end

  test "eine Teilzahlung wird nicht automatisch zugeordnet" do
    ki = kreditor("Teilzahler GmbH")
    eingangsbeleg(ki.uuid, 119)
    umsatz(-60, counterparty_knowledge_item_uuid: ki.uuid)

    assert_equal 0, Bank::ObligationMatch.auto(@konto), "nur betragsexakt"
  end

  test "ein bewusst ohne Zuordnung markierter Umsatz wird nicht mehr angefasst" do
    ki = kreditor("Bank AG")
    eingangsbeleg(ki.uuid, 4.90)
    tx = umsatz(-4.90, counterparty_knowledge_item_uuid: ki.uuid)
    tx.mark_no_assignment!("Kontoführungsentgelt")

    assert_equal 0, Bank::ObligationMatch.auto(@konto)
  end

  # ── Gegenrichtung ─────────────────────────────────────────────────────

  test "eine neu erfasste Pflicht findet den passenden Umsatz" do
    ki = kreditor("Später GmbH")
    umsatz(-333, counterparty_knowledge_item_uuid: ki.uuid)
    beleg = eingangsbeleg(ki.uuid, 333)

    assert Bank::ObligationMatch.match_for_obligation(beleg.payment_obligations.sole)
    assert_equal "bezahlt", beleg.reload.payment_status
  end

  # ── Überfälligkeits-Hinweis ───────────────────────────────────────────

  # Der Fehler, mit dem das ganze Vorhaben anfing: Ein Bescheid ohne
  # Zahlungspflicht mahnte 909 € an, die es nie gab.
  test "überfällig fragt die Zahlungspflichten, nicht den Beleg" do
    ki = kreditor("Versorger AG")
    faellig = eingangsbeleg(ki.uuid, 119)
    faellig.payment_obligations.sole.update!(due_on: Date.current - 3)

    bescheid = Invoice.create!(kind: :rechnung, direction: :eingehend,
                               document_type: :bescheid, issuer_uuid: ki.uuid)

    assert_includes     Invoice.overdue, faellig
    assert_not_includes Invoice.overdue, bescheid, "ohne Zahlungspflicht keine Mahnung"

    Bank::ObligationMatch.assign(umsatz(-119, counterparty_knowledge_item_uuid: ki.uuid),
                                 faellig.payment_obligations.sole)
    assert_not_includes Invoice.overdue, faellig.reload, "getilgt ist nicht überfällig"
  end
end
