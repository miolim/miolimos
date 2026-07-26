# #1171 (aus immoOS #1069 übernommen): „Eheleute Mustermann" als Adressat.
#
# Der Empfänger eines Belegs ist strikt EIN KnowledgeItem — das reicht
# nicht, wenn mehrere Personen gemeinsam adressiert werden sollen.
# documents.recipient_label ist die optionale, bewusst gewählte Kurzform
# fürs Anschriftfeld; leer = wie bisher der Titel des Empfänger-KIs.
# Bewusst keine Ableitung aus gleichem Nachnamen: das rät bei Geschwistern,
# WGs und Doppelnamen falsch, und zwar auf dem Briefkopf.
class AddRecipientLabelToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :recipient_label, :string, null: true
  end
end
