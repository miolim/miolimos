# Item-Type-Konsolidierung — Klassifikation nach Beziehung zur Source
# statt nach Medium:
#
#   ai_chat (1)  → abstract       (Wert 1, nur umbenannt)
#   web_clip (2) → transcript     (Wert 2, nur umbenannt)
#   quote (3)    → direct_quote   (Wert 3, nur umbenannt)
#   document (4) → transcript     (Wert 4 → 2, Daten verschoben)
#   indirect_quote                (neu, Wert 9)
#
# Frontmatter der MD-Files wird durch ein separates Backfill-Skript
# umgeschrieben; der Indexer akzeptiert solange die alten Strings als
# Aliase, sodass der Bestand nicht kaputtgeht.
class ConsolidateKnowledgeItemTypes < ActiveRecord::Migration[8.1]
  def up
    # Alle bisherigen `document`-KIs (4) werden zu `transcript` (2). Das
    # Attachment (file_path zeigt auf PDF) bleibt am KI hängen — neu ist
    # nur die semantische Etikettierung. Den Volltext liefert ein
    # späterer Pipeline-Schritt nach (PDF-Text-Extraktion).
    execute "UPDATE knowledge_items SET item_type = 2 WHERE item_type = 4"
  end

  def down
    # Best-effort-Rollback: KIs, deren file_path auf nicht-Markdown
    # zeigt, waren ursprünglich `document`. Heuristik OK für unsere
    # Daten, kein 100%-Inverter.
    execute <<~SQL
      UPDATE knowledge_items
         SET item_type = 4
       WHERE item_type = 2
         AND file_path NOT LIKE '%.md'
    SQL
  end
end
