class CreateCommentReads < ActiveRecord::Migration[8.1]
  def change
    create_table :comment_reads do |t|
      t.references :actor,        null: false, foreign_key: { on_delete: :cascade }
      t.references :task_comment, null: false, foreign_key: { on_delete: :cascade }
      t.datetime   :read_at,      null: false
      t.timestamps
    end
    add_index :comment_reads, [:actor_id, :task_comment_id], unique: true
  end
end
