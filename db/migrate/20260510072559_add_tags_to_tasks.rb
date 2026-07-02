class AddTagsToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :tags, :string, array: true, default: [], null: false
    add_index  :tasks, :tags, using: :gin
  end
end
