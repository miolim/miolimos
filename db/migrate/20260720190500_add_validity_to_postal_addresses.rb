# #1073 (Hans, 2026-07-20): Adressen bekommen Gueltigkeitszeitraeume, damit
# die frühere Anschrift einer Person erhalten bleibt, wenn sie umzieht (in
# der Hausverwaltung: der Mieter zieht in das verwaltete Objekt — die alte
# Postadresse bleibt fuer Schriftverkehr vor dem Einzug relevant).
#
# Beide Spalten sind nullable: leer = unbefristet. Bestandsdaten sind damit
# ohne Backfill korrekt (alles gilt weiterhin unbefristet).
class AddValidityToPostalAddresses < ActiveRecord::Migration[8.1]
  def change
    add_column :postal_addresses, :valid_from,  :date
    add_column :postal_addresses, :valid_until, :date
  end
end
