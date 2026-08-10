require "test_helper"

# #1337 Schnitt 1: Bankkonto, Auszug, Umsatz. Geprüft wird das, was im
# immoOS-Fork im Betrieb Geld gekostet hat — Dublettenschutz, Vorzeichen,
# Herkunft, „bewusst ohne Zuordnung" und der Restbetrag.
class BankTransactionTest < ActiveSupport::TestCase
  setup do
    @konto = BankLedger.create!(label: "Geschäftskonto", iban: "de89 3704 0044 0532 0130 00",
                                opening_balance: 1000, opening_on: Date.new(2026, 1, 1))
  end

  def umsatz(**attrs)
    @konto.bank_transactions.create!(
      { booked_on: Date.new(2026, 3, 1), amount: -119, purpose: "Stadtwerke Abschlag" }.merge(attrs)
    )
  end

  test "IBAN und BIC werden normalisiert" do
    assert_equal "DE89370400440532013000", @konto.iban
  end

  # Der Saldo gilt bis zur jüngsten Buchung, nicht bis heute.
  test "Saldo ist Anfangssaldo plus Umsätze, mit Stichtag der jüngsten Buchung" do
    assert_equal BigDecimal("1000"), @konto.balance
    assert_equal Date.new(2026, 1, 1), @konto.balance_on, "ohne Umsätze zählt der Anfangsstichtag"

    umsatz(amount: -119, booked_on: Date.new(2026, 3, 1))
    umsatz(amount: 500,  booked_on: Date.new(2026, 2, 1), purpose: "Eingang")
    assert_equal BigDecimal("1381"), @konto.reload.balance
    assert_equal Date.new(2026, 3, 1), @konto.balance_on
  end

  # Ein Auszug wird garantiert zweimal importiert — von Hand, nach einem
  # Abbruch, oder weil sich Zeiträume überlappen.
  test "derselbe Umsatz kann im selben Konto nicht zweimal entstehen" do
    umsatz(bank_ref: "REF-4711")
    doppelt = @konto.bank_transactions.build(booked_on: Date.new(2026, 3, 1), amount: -119,
                                             bank_ref: "REF-4711")
    assert_not doppelt.valid?
    assert_includes doppelt.errors.attribute_names, :fingerprint
  end

  test "derselbe Umsatz in einem ANDEREN Konto ist kein Duplikat" do
    umsatz(bank_ref: "REF-4711")
    zweites = BankLedger.create!(label: "Zweitkonto")
    assert zweites.bank_transactions.create!(booked_on: Date.new(2026, 3, 1), amount: -119,
                                             bank_ref: "REF-4711").persisted?
  end

  test "ohne Bank-Referenz kommt der Fingerprint aus den Kernfeldern" do
    tx = umsatz
    assert_equal 64, tx.fingerprint.length, "SHA256-Hex"
    gleich = @konto.bank_transactions.build(booked_on: Date.new(2026, 3, 1), amount: -119,
                                            purpose: "Stadtwerke Abschlag")
    gleich.valid?
    assert_equal tx.fingerprint, gleich.fingerprint, "deterministisch — sonst greift der Schutz nicht"
  end

  test "Vorzeichen wie auf dem Kontoauszug" do
    assert umsatz(amount: -119).withdrawal?
    assert umsatz(amount: 500, purpose: "Eingang").deposit?
  end

  # Ohne dieses Merkmal steht ein Drittel des Kontos für immer als „nicht
  # zugeordnet" da, und die Liste wird wertlos.
  test "bewusst ohne Zuordnung ist eine Entscheidung, keine Lücke" do
    tx = umsatz(purpose: "Kontoführungsentgelt")
    assert_includes BankTransaction.unentschieden, tx

    tx.mark_no_assignment!("Kontoführung, kein Beleg")
    assert tx.no_assignment?
    assert_not_includes BankTransaction.unentschieden, tx.reload
    assert_equal "Kontoführung, kein Beleg", tx.no_assignment_note

    tx.clear_no_assignment!
    assert_includes BankTransaction.unentschieden, tx.reload
  end

  # Ein Umsatz ist erst erledigt, wenn er ausgeschöpft ist — nicht schon nach
  # der ersten Zuordnung. Die Tilgungen kommen in Schnitt 2.
  test "Restbetrag ist vorzeichenlos und in Schnitt 1 der volle Betrag" do
    assert_equal BigDecimal("119"), umsatz(amount: -119).restbetrag
    assert umsatz(amount: 500, purpose: "Eingang").rest_offen?
  end

  test "Suche findet Text und Betrag, mit und ohne Vorzeichen" do
    tx = umsatz(amount: -119, purpose: "Stadtwerke Abschlag", counterparty_name: "Stadtwerke")
    assert_includes BankTransaction.suche("stadtwerke"), tx
    assert_includes BankTransaction.suche("119,00"),     tx, "Betrag ohne Vorzeichen muss finden"
    assert_includes BankTransaction.suche("-119"),       tx
    assert_empty    BankTransaction.suche("Telekom")
  end

  # Ohne die Herkunft ist eine fehlerhafte Einlieferung nicht herauszulösen.
  test "der Auszug trägt seine Umsätze und nimmt sie beim Rückgängigmachen mit" do
    auszug = @konto.bank_statements.create!(filename: "auszug-03.csv", format: "csv",
                                            period_from: Date.new(2026, 3, 1),
                                            period_to: Date.new(2026, 3, 31))
    umsatz(bank_statement: auszug)
    umsatz(bank_statement: auszug, amount: -50, purpose: "Telekom")
    einzeln = umsatz(amount: -10, purpose: "von Hand")

    assert_equal 2, auszug.bank_transactions.count
    assert_equal "01.03.2026 – 31.03.2026", auszug.period

    assert_difference -> { BankTransaction.count }, -2 do
      auszug.revert!
    end
    assert BankTransaction.exists?(einzeln.id), "von Hand erfasste Umsätze bleiben"
  end

  # Der Gegenpart als Verknüpfung, nicht als Name: Ein Textfeld löst still auf
  # nichts auf, und niemand merkt es.
  test "Gegenpart kann als Verknüpfung hängen, unabhängig vom Namen im Auszug" do
    uuid = SecureRandom.uuid
    tx = umsatz(counterparty_knowledge_item_uuid: uuid, counterparty_name: "STADTWERKE BEISPIELSTADT")
    assert_equal uuid, tx.reload.counterparty_knowledge_item_uuid
    assert_equal "STADTWERKE BEISPIELSTADT", tx.counterparty_name,
                 "der Name aus dem Auszug bleibt daneben stehen — er ist der Nachweis"
  end

  # Die Entkopplung, um die es bei der Wanderung geht.
  test "der Umsatz kennt keine Mieterzahlung" do
    assert_not BankTransaction.column_names.include?("tenant_payment_id"),
               "hausverwaltungsspezifischer Fremdschlüssel gehört nicht an die allgemeine Entität"
  end
end
