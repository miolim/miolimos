class AddWipActorIdToTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :tasks, :wip_actor, foreign_key: { to_table: :actors }, null: true
    add_index :tasks, :wip_actor_id, where: "wip_actor_id IS NOT NULL", name: "index_tasks_on_wip_actor_id_not_null"
  end
end
