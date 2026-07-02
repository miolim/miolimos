# #541 (Hans, 2026-06-08): Leistungszeitraum der Rechnung (§14 UStG Pflichtfeld).
# service_start allein = Leistungsdatum; mit service_end = Zeitraum von–bis.
class AddServicePeriodToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :service_start, :date
    add_column :documents, :service_end, :date
  end
end
