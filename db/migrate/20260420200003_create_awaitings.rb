class CreateAwaitings < ActiveRecord::Migration[8.1]
  def change
    create_table :awaitings do |t|
      t.text       :description,     null: false
      t.integer    :status,          null: false, default: 0
      t.date       :follow_up_at,    null: false
      t.datetime   :resolved_at
      t.text       :resolution_note

      t.references :creator,       null: false, foreign_key: { to_table: :actors }
      t.references :contact,       foreign_key: true
      t.references :communication, foreign_key: true
      t.references :task,          foreign_key: true

      t.timestamps
    end

    # Häufigste Query: open awaitings sortiert nach follow_up_at.
    add_index :awaitings, [:status, :follow_up_at]

    create_table :awaiting_topics do |t|
      t.references :awaiting, null: false, foreign_key: true
      t.references :topic,    null: false, foreign_key: true
    end
    add_index :awaiting_topics, [:awaiting_id, :topic_id], unique: true
  end
end
