# #516 (Hans, 2026-06-05): Identifizierung an die Verknüpfung Quelle↔Autor
# hängen (nicht an die Person). Eine source_creators-Zeile ist die Aussage
# „diese Person ist Rolleninhaber dieser Quelle" — mit Status (provisorisch
# / identifiziert), Konfidenz und Provenienz (worauf gestützt). Spiegelt
# das recognized_*-Muster der relations.
class AddIdentificationToSourceCreators < ActiveRecord::Migration[8.1]
  def change
    add_column :source_creators, :identification, :string, null: false, default: "provisional"
    add_column :source_creators, :confidence, :string
    add_column :source_creators, :identified_via, :string
    add_column :source_creators, :identified_by_id, :bigint
    add_column :source_creators, :identified_at, :datetime

    add_index :source_creators, :identification
  end
end
