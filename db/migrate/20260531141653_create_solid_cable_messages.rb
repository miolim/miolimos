# #232 Phase 0: solid_cable-Messages-Tabelle auf der primary-DB.
# Schema 1:1 aus solid_cable's cable_schema.rb (v4.0.0) uebernommen,
# als regulaere Migration, damit sie in db/structure.sql landet und der
# Deploy-`rails db:migrate` sie anwendet.
class CreateSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages do |t|
      t.binary   :channel,      limit: 1024,       null: false
      t.binary   :payload,      limit: 536_870_912, null: false
      t.datetime :created_at,                       null: false
      t.integer  :channel_hash, limit: 8,          null: false
    end
    add_index :solid_cable_messages, :channel,      name: "index_solid_cable_messages_on_channel"
    add_index :solid_cable_messages, :channel_hash, name: "index_solid_cable_messages_on_channel_hash"
    add_index :solid_cable_messages, :created_at,   name: "index_solid_cable_messages_on_created_at"
  end
end
