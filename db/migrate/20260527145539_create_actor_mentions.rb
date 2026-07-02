# #384 Phase 2 (Hans, 2026-05-27): Adressierungs-Mentions auf App-
# Nutzer (Actor). Anders als knowledge_item_mentions (KI -> KI, fuer
# Wikilinks auf Person-KIs etc.) verweist diese Join-Tabelle ein KI
# auf einen ADRESSIERBAREN Actor (HumanActor oder AgentActor) — also
# jemand, der Inbox + Login-Pfad hat und auf eine Adressierung
# reagieren kann.
class CreateActorMentions < ActiveRecord::Migration[8.1]
  def change
    create_table :actor_mentions do |t|
      t.string  :knowledge_item_uuid, null: false
      t.bigint  :actor_id,            null: false
      t.timestamps
    end

    add_index :actor_mentions, [:knowledge_item_uuid, :actor_id],
              unique: true, name: "index_actor_mentions_pair"
    add_index :actor_mentions, :actor_id
    add_foreign_key :actor_mentions, :knowledge_items,
                    column: :knowledge_item_uuid, primary_key: :uuid
    add_foreign_key :actor_mentions, :actors
  end
end
