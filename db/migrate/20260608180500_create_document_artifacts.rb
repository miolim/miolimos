# #532 (Hans, 2026-06-08): festgeschriebene PDF-Stände eines Dokuments. Bei
# Status "final" wird das erzeugte PDF dauerhaft archiviert (mit Ersteller +
# Zeitpunkt), damit ein fester Stand bleibt, auch wenn die Quelldaten sich
# später ändern. PDF-Bytes liegen in der DB (bytea) — Volumen ist klein.
class CreateDocumentArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :document_artifacts do |t|
      t.references :document, null: false, foreign_key: true
      t.binary  :pdf,     null: false           # die festgeschriebenen PDF-Bytes
      t.boolean :signed,  null: false, default: false
      t.bigint  :creator_id                     # Actor
      t.timestamps
    end
  end
end
