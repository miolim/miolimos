# #1337 Schnitt 2: der offene-Posten-Ausgleich.
#
# Eine Tilgung hängt an der ZAHLUNGSPFLICHT, nicht am Beleg. Genau daran
# scheitert der Aufbau im Fork: Bei einem Beleg mit mehreren Fälligkeiten
# (Grundsteuerbescheid mit vier Quartalsraten) ist sonst nicht entscheidbar,
# welche Rate ein Umsatz getilgt hat. Deshalb heißt die Tabelle
# `obligation_settlements` und nicht `invoice_settlements` — mit
# immoos_builder so abgestimmt, weil zwei Tabellen gleichen Namens mit
# verschiedener Bedeutung die teuerste Merge-Kollision wären.
#
# VORZEICHEN: `amount` trägt dasselbe Vorzeichen wie die Pflicht und wie der
# tilgende Umsatz — Geldrichtung aus eigener Sicht. Eine fremde Rechnung ist
# eine negative Pflicht, die Auszahlung ein negativer Umsatz, die Tilgung
# negativ. Eine Gutschrift ist positiv und wird durch eine positive Erstattung
# getilgt. Damit braucht keine Rechenstelle eine Fallunterscheidung; im Fork
# hat die umgekehrte Wahl ein vollständig erstattetes Guthaben lautlos aus der
# Betriebskostenabrechnung fallen lassen (#1329).
#
# Eine eigene TABELLE, kein Fremdschlüssel an der Pflicht: Der Fork hat den
# 1:1-Schlüssel zweimal gebaut und ersetzen müssen (#1017/#1021). Nur so sind
# Teilzahlung, Überzahlung und die Sammelüberweisung abbildbar, die mehrere
# Pflichten tilgt.
class CreateObligationSettlements < ActiveRecord::Migration[8.0]
  def change
    create_table :obligation_settlements do |t|
      t.references :payment_obligation, null: false, foreign_key: true
      # Leer bei Ausbuchung und bei einem Vermerk von Hand — beides ist eine
      # Tilgung ohne Umsatz.
      t.references :bank_transaction,   null: true,  foreign_key: true
      t.integer  :kind,   null: false, default: 0
      t.decimal  :amount, precision: 12, scale: 2, null: false
      t.string   :note
      t.date     :settled_on
      t.timestamps
    end

    # Derselbe Umsatz tilgt dieselbe Pflicht höchstens einmal. Teilbeträge
    # gehören in EINE Zeile, sonst ist der Rest nicht mehr nachvollziehbar.
    add_index :obligation_settlements, [:payment_obligation_id, :bank_transaction_id],
              unique: true, where: "bank_transaction_id IS NOT NULL",
              name: "idx_obligation_settlement_unique_tx"
  end
end
