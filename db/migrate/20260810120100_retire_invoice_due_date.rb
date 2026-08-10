# #1336 Stufe 2, zweiter Teil: `invoices.due_date` fällt weg, `payment_status`
# wird zur reinen Ableitung.
#
# `due_date` FÄLLT WEG (Hans, #1336): Bei vier Quartalsraten gibt es keine
# Fälligkeit DES BELEGS. Eine Cache-Spalte müsste „nächste offene" bedeuten
# und stünde genau dann falsch, wenn es darauf ankommt. Was gebraucht wird,
# ist eine abgeleitete Lesemethode — `Invoice#next_due_on`.
#
# `payment_status` BLEIBT als nachgeführte Ableitungsspalte, damit „offene
# Eingangsbelege" in SQL filterbar bleibt, ohne den halben Bestand in den
# Speicher zu laden. Sie hat ab jetzt keinen Schreibweg mehr aus der
# Oberfläche; sie wird aus den Zahlungspflichten neu berechnet.
#
# Sie wird dabei NULL-fähig: Ein Beleg ohne Zahlungspflicht (Bescheid,
# Vertrag, Kontoauszug) hat keinen Zahlstatus — weder „offen" noch „bezahlt".
# NULL ist hier die richtige Aussage, und sie ist zugleich der Schutz, um den
# es in diesem Vorhaben geht: `WHERE payment_status = 0` findet ihn nicht,
# ohne dass jemand eine Regel befolgen muss.
class RetireInvoiceDueDate < ActiveRecord::Migration[8.0]
  def up
    change_column_null    :invoices, :payment_status, true
    change_column_default :invoices, :payment_status, from: 0, to: nil

    # Belege ohne Zahlungspflicht haben keinen Zahlstatus mehr.
    execute <<~SQL.squish
      UPDATE invoices SET payment_status = NULL
      WHERE NOT EXISTS (
        SELECT 1 FROM payment_obligations o
        WHERE o.bearer_type = 'Invoice' AND o.bearer_id = invoices.id
      )
    SQL

    remove_column :invoices, :due_date
  end

  def down
    add_column :invoices, :due_date, :date
    execute <<~SQL.squish
      UPDATE invoices SET due_date = (
        SELECT MIN(o.due_on) FROM payment_obligations o
        WHERE o.bearer_type = 'Invoice' AND o.bearer_id = invoices.id
          AND o.amount <> o.settled_amount
      )
    SQL
    execute "UPDATE invoices SET payment_status = 0 WHERE payment_status IS NULL"
    change_column_default :invoices, :payment_status, from: nil, to: 0
    change_column_null    :invoices, :payment_status, false
  end
end
