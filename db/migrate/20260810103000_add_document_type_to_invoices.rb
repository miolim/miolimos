# #1336 Stufe 1 (aus immoOS): Belegart speichern statt verwerfen.
#
# Der Dokumenten-Import erkennt den Typ des Schriftstücks (Rechnung,
# Bescheid, Versicherungsschein …) und wirft ihn anschließend weg —
# `create_incoming_invoice` schreibt fest `kind: :rechnung`. Im Bestand
# sind die Arten danach nicht mehr unterscheidbar.
#
# Bewusst NICHT in `kind` (rechnung/angebot) hineingelegt: dort hängen
# Nummernkreise, Rendering und E-Rechnung; ein neuer Wert dort verfälscht
# stillschweigend Zähler und Filter. Die Belegart ist ein eigenes Merkmal.
#
# NULL-fähig: leer heißt „Art unbekannt/nicht erfasst" — Bestandsbelege
# bleiben damit unverändert, kein Backfill nötig.
class AddDocumentTypeToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :document_type, :integer, null: true
  end
end
