class CreateContactPoints < ActiveRecord::Migration[8.1]
  def up
    create_table :contact_points do |t|
      # FK ans Person/Org-KI über uuid (KIs nutzen uuid als PK).
      t.string  :knowledge_item_uuid, null: false

      # Schema.org-inspiriert: Art der Adresse + Label + Wert.
      # kind ∈ {email, phone, address, url, fax, im}; label frei
      # ("private", "work", "mobile" …); value als String, weil
      # Postadressen mehrzeilig sein können.
      t.string  :kind,  null: false
      t.string  :label, default: ""
      t.text    :value, null: false

      # Sortierreihenfolge im Editor.
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :contact_points, :knowledge_item_uuid
    add_index :contact_points, :kind
    add_index :contact_points, [:knowledge_item_uuid, :kind, :position]
    # Schneller Lookup für GmailSync: Person-KI über E-Mail-Adresse.
    add_index :contact_points, "lower(value)", name: "idx_contact_points_lower_value"

    # Bestehende Single-Value-Spalten in contact_points migrieren
    # (auf prod 0 Zeilen, aber sauber). Anschließend droppen.
    execute <<~SQL
      INSERT INTO contact_points (knowledge_item_uuid, kind, label, value, position, created_at, updated_at)
      SELECT uuid, 'email',   '', email,   0, NOW(), NOW()
      FROM knowledge_items
      WHERE email IS NOT NULL AND email <> ''
        AND item_type IN (6, 7); -- person, organization
    SQL
    execute <<~SQL
      INSERT INTO contact_points (knowledge_item_uuid, kind, label, value, position, created_at, updated_at)
      SELECT uuid, 'phone',   '', phone,   0, NOW(), NOW()
      FROM knowledge_items
      WHERE phone IS NOT NULL AND phone <> ''
        AND item_type IN (6, 7);
    SQL
    execute <<~SQL
      INSERT INTO contact_points (knowledge_item_uuid, kind, label, value, position, created_at, updated_at)
      SELECT uuid, 'url', 'website', website, 0, NOW(), NOW()
      FROM knowledge_items
      WHERE website IS NOT NULL AND website <> ''
        AND item_type IN (6, 7);
    SQL

    remove_index :knowledge_items, name: "idx_kis_lower_email" if index_exists?(:knowledge_items, :email, name: "idx_kis_lower_email")
    remove_column :knowledge_items, :email
    remove_column :knowledge_items, :phone
    remove_column :knowledge_items, :website
  end

  def down
    add_column :knowledge_items, :email,   :string
    add_column :knowledge_items, :phone,   :string
    add_column :knowledge_items, :website, :string
    add_index  :knowledge_items, "lower(email)", name: "idx_kis_lower_email"

    # Erste Werte je kind zurückkopieren (Verlust von zusätzlichen, mehr
    # geht nicht in einzelne Spalten).
    execute <<~SQL
      UPDATE knowledge_items SET email = cp.value
      FROM contact_points cp
      WHERE cp.knowledge_item_uuid = knowledge_items.uuid
        AND cp.kind = 'email' AND cp.position = 0;
    SQL

    drop_table :contact_points
  end
end
