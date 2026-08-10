# #1336 (Nachtrag zu Stufe 1): Belegart string- statt integer-hinterlegt.
#
# Das Konzept „immoOS — Belege, Vorgänge und ihre Benennung" hält die
# Belegarten ausdrücklich OFFEN: eine neue Art ist eine Beschriftung plus
# eine Vorbelegung, kein neuer Programmpfad. Ein Integer-Enum steht dem
# zweifach entgegen:
#
#   1. Die Zahl→Name-Zuordnung lebt nur im Code. Sie muss zwischen miolimOS
#      und dem immoOS-Fork auf ewig identisch bleiben — vergibt eine Seite
#      die 6 an „kaution", die andere an „mahnung", verschiebt der Merge die
#      Bedeutung des Bestands, ohne dass etwas fehlschlägt.
#   2. In der Datenbank steht `document_type = 1` statt `bescheid`. Für
#      Belege, deren Zweck der Nachweis ist, ist das die falsche Richtung.
#
# Bestand: die Spalte ist an dieser Stelle produktiv noch leer (0 Zeilen);
# die Abbildung unten ist trotzdem vollständig, damit die Migration auch in
# Installationen trägt, die zwischen beiden Deploys importiert haben.
class ChangeInvoicesDocumentTypeToString < ActiveRecord::Migration[8.0]
  MAPPING = {
    0 => "rechnung", 1 => "bescheid", 2 => "versicherung",
    3 => "anschreiben", 4 => "vertrag", 5 => "sonstiges"
  }.freeze

  def up
    cases = MAPPING.map { |i, name| "WHEN #{i} THEN '#{name}'" }.join(" ")
    execute <<~SQL.squish
      ALTER TABLE invoices
        ALTER COLUMN document_type TYPE character varying
        USING (CASE document_type #{cases} ELSE NULL END)
    SQL
  end

  def down
    cases = MAPPING.map { |i, name| "WHEN '#{name}' THEN #{i}" }.join(" ")
    execute <<~SQL.squish
      ALTER TABLE invoices
        ALTER COLUMN document_type TYPE integer
        USING (CASE document_type #{cases} ELSE NULL END)
    SQL
  end
end
