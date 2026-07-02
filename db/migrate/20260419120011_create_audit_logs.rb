class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :actor, null: false, foreign_key: true
      t.string :action, null: false
      t.references :auditable, polymorphic: true, null: false
      t.jsonb :changes_data, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end
