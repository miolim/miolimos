# #1057 (aus immoos #1031, Hans): Rechtsform einer Organisation (fakultativ).
# In immoos als Fork-Stopgap entstanden (WEG-Erkennung: Grundstücks-Eigentümerin
# ist eine GdWE) und dort explizit zur Upstream-Übernahme markiert. Der Kern
# führt das Feld als reines Stammdatum; Katalog siehe app/models/legal_forms.rb.
class AddLegalFormToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :legal_form, :string, null: true
  end
end
