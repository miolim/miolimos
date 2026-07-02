# #544 (Hans, 2026-06-08): USt-IdNr (vat_id) und ORCID leben künftig im
# IDs-Bereich (Identifier) statt als Sonderspalten. Bestandswerte werden
# als Identifier-Zeilen übernommen (idempotent). Die Spalten bleiben vorerst
# als Fallback bestehen; Renderer liest bevorzugt den Identifier.
class MigrateVatOrcidToIdentifiers < ActiveRecord::Migration[8.1]
  def up
    # person(6) / organization(7)
    execute(<<~SQL)
      INSERT INTO identifiers (knowledge_item_uuid, label, value, position, created_at, updated_at)
      SELECT k.uuid, 'USt-IdNr', k.vat_id, 0, now(), now()
      FROM knowledge_items k
      WHERE k.vat_id IS NOT NULL AND k.vat_id <> '' AND k.item_type IN (6, 7)
        AND NOT EXISTS (
          SELECT 1 FROM identifiers i
          WHERE i.knowledge_item_uuid = k.uuid AND lower(i.label) = lower('USt-IdNr')
        );
    SQL
    execute(<<~SQL)
      INSERT INTO identifiers (knowledge_item_uuid, label, value, position, created_at, updated_at)
      SELECT k.uuid, 'ORCID', k.orcid, 0, now(), now()
      FROM knowledge_items k
      WHERE k.orcid IS NOT NULL AND k.orcid <> '' AND k.item_type IN (6, 7)
        AND NOT EXISTS (
          SELECT 1 FROM identifiers i
          WHERE i.knowledge_item_uuid = k.uuid AND lower(i.label) = lower('ORCID')
        );
    SQL
  end

  def down
    # Übernahme nicht rückgängig machen (Identifier sind jetzt führend).
  end
end
