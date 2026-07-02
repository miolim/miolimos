class Phase2CutContacts < ActiveRecord::Migration[8.1]
  def up
    # 1. Neue FK-/Join-Strukturen anlegen, mit Daten aus den alten füllen.
    add_column :awaitings, :contact_uuid, :string
    add_index  :awaitings, :contact_uuid

    create_table :knowledge_item_mentions do |t|
      t.string :knowledge_item_uuid, null: false
      t.string :mentioned_uuid, null: false
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :knowledge_item_mentions, :knowledge_item_uuid
    add_index :knowledge_item_mentions, :mentioned_uuid
    add_index :knowledge_item_mentions, [:knowledge_item_uuid, :mentioned_uuid],
              unique: true, name: "idx_kim_unique"

    create_table :task_mentions do |t|
      t.bigint :task_id, null: false
      t.string :mentioned_uuid, null: false
      t.timestamps
    end
    add_index :task_mentions, :task_id
    add_index :task_mentions, :mentioned_uuid
    add_index :task_mentions, [:task_id, :mentioned_uuid], unique: true, name: "idx_tm_unique"

    create_table :communication_mentions do |t|
      t.bigint :communication_id, null: false
      t.string :mentioned_uuid, null: false
      t.string :role, default: ""
      t.timestamps
    end
    add_index :communication_mentions, :communication_id
    add_index :communication_mentions, :mentioned_uuid
    add_index :communication_mentions, [:communication_id, :mentioned_uuid, :role],
              unique: true, name: "idx_cm_unique"

    # 2. Daten kopieren — Contact.knowledge_item_uuid wurde in Phase 1
    #    befüllt, also können wir die alten FKs darüber auflösen.
    execute <<~SQL
      UPDATE awaitings SET contact_uuid = c.knowledge_item_uuid
      FROM contacts c
      WHERE awaitings.contact_id = c.id
        AND c.knowledge_item_uuid IS NOT NULL;
    SQL

    execute <<~SQL
      INSERT INTO knowledge_item_mentions (knowledge_item_uuid, mentioned_uuid, position, created_at, updated_at)
      SELECT kic.knowledge_item_uuid, c.knowledge_item_uuid, 0, NOW(), NOW()
      FROM knowledge_item_contacts kic
      JOIN contacts c ON c.id = kic.contact_id
      WHERE c.knowledge_item_uuid IS NOT NULL
      ON CONFLICT DO NOTHING;
    SQL

    execute <<~SQL
      INSERT INTO task_mentions (task_id, mentioned_uuid, created_at, updated_at)
      SELECT tc.task_id, c.knowledge_item_uuid, NOW(), NOW()
      FROM task_contacts tc
      JOIN contacts c ON c.id = tc.contact_id
      WHERE c.knowledge_item_uuid IS NOT NULL
      ON CONFLICT DO NOTHING;
    SQL

    execute <<~SQL
      INSERT INTO communication_mentions (communication_id, mentioned_uuid, role, created_at, updated_at)
      SELECT cc.communication_id, c.knowledge_item_uuid,
             CASE cc.role
               WHEN 0 THEN 'sender'
               WHEN 1 THEN 'recipient'
               WHEN 2 THEN 'cc'
               WHEN 3 THEN 'bcc'
               ELSE ''
             END,
             NOW(), NOW()
      FROM communication_contacts cc
      JOIN contacts c ON c.id = cc.contact_id
      WHERE c.knowledge_item_uuid IS NOT NULL
      ON CONFLICT DO NOTHING;
    SQL

    # 3. Alte Tabellen + Spalten weg.
    remove_column :awaitings, :contact_id
    drop_table :knowledge_item_contacts
    drop_table :task_contacts
    drop_table :communication_contacts
    drop_table :contacts
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Phase 2 cut is one-way."
  end
end
