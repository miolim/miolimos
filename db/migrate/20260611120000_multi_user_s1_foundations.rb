# #602 S1 (Hans, 2026-06-11): Multi-User-Fundament — Nutzer-Rollen,
# Topic-Mitgliedschaften und Topic-Sichtbarkeit. Die Sichtbarkeits-
# Auswertung passiert in den visible_to-Scopes (Modelle), nicht hier.
class MultiUserS1Foundations < ActiveRecord::Migration[8.0]
  def up
    # Rolle am Actor: admin sieht alles (heutiges Verhalten), member sieht
    # nur Mitglieds-Topics + Eigenes, guest ist für S3 reserviert.
    # Default member = default-deny für NEUE Nutzer; Bestand wird admin,
    # damit sich für Hans (und die Test-Accounts) nichts ändert.
    add_column :actors, :role, :integer, null: false, default: 1
    execute "UPDATE actors SET role = 0 WHERE type = 'HumanActor'"

    # Sichtbarkeit am Topic: members_only (default-deny) oder
    # internal_public (alle internen Nutzer — Glossar, Handbuch, Vorlagen).
    add_column :topics, :visibility, :integer, null: false, default: 0

    create_table :topic_memberships do |t|
      t.references :topic, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true
      # viewer/editor/owner — S1 speichert die Rolle (UI + Datenmodell),
      # die Schreibrechte-Auswertung (viewer = read-only) kommt in S2.
      t.integer :role, null: false, default: 0
      t.timestamps
    end
    add_index :topic_memberships, [:topic_id, :actor_id], unique: true
  end

  def down
    drop_table :topic_memberships
    remove_column :topics, :visibility
    remove_column :actors, :role
  end
end
