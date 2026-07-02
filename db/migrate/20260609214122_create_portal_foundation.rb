# #536 P1: Fundament des Kundenportals.
# - portal_accesses: WER (E-Mail, optional Kunde-KI) darf WELCHES Projekt
#   (Topic) sehen. Magic-Links sind zustandslos signiert (kein Token hier);
#   last_login_at fürs Auditing, active als Kill-Switch.
# - tasks.client_milestone: kuratierte Roadmap-Punkte (dedizierter Bool,
#   bewusst KEIN Tag — sichtbarkeitsrelevant, siehe Thread).
# - document_artifacts.shared_with_client: Freigabe je eingefrorenem Stand
#   (das Artefakt ist die Einheit des Teilens, nie der lebende Entwurf).
# - communications.portal_visible: welche Nachrichten der Projekt-Thread
#   im Portal zeigt (Kunden-Posts true ab Entstehung; Hans' Antworten
#   explizit beim Senden).
class CreatePortalFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_accesses do |t|
      t.references :topic, null: false, foreign_key: true
      t.string  :knowledge_item_uuid              # Kunde als Person/Org-KI (optional)
      t.string  :email, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :portal_accesses, [ :topic_id, :email ], unique: true
    add_index :portal_accesses, :email

    add_column :tasks, :client_milestone, :boolean, null: false, default: false
    add_column :document_artifacts, :shared_with_client, :boolean, null: false, default: false
    add_column :communications, :portal_visible, :boolean, null: false, default: false
  end
end
