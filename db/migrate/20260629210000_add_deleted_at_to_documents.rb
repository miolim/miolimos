# #787 (Hans): Dokumente löschbar machen — Soft-Delete (Papierkorb) analog
# zu KnowledgeItem/Task (deleted_at + default_scope). Finale PDFs (Artefakte)
# werden hart gelöscht (eigene Aktion), das braucht keine Spalte.
class AddDeletedAtToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :deleted_at, :datetime
    add_index  :documents, :deleted_at
  end
end
