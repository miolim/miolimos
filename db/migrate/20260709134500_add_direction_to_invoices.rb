# #934 (Hans, 2026-07-09): Eingangsrechnungen. Eingehende und ausgehende
# Rechnungen teilen die Struktur (Parteien, Positionen, Beträge) — statt
# einer neuen Entität bekommt Invoice eine Richtung. Eingehende tragen
# zusätzlich Fälligkeit + Zahlstatus; das Original-PDF hängt als Artefakt
# in der polymorphen Schicht (#926).
class AddDirectionToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :direction, :integer, null: false, default: 0   # ausgehend
    add_column :invoices, :due_date, :date
    add_column :invoices, :payment_status, :integer, null: false, default: 0  # offen
    add_index  :invoices, :direction
  end
end
