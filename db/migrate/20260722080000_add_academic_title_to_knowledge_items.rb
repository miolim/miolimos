# #1090 Nachtrag (Hans): akademischer Titel als eigenes Stammdaten-Feld
# (Freitext, z. B. „Dr.", „Prof. Dr."). Fliesst in die Briefanrede UND in
# die Namenszeile des DIN-Anschriftfelds ein — deshalb eigenes Feld statt
# Freitext-Anrede.
class AddAcademicTitleToKnowledgeItems < ActiveRecord::Migration[8.0]
  def change
    add_column :knowledge_items, :academic_title, :string, null: true
  end
end
