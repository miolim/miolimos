class CreateTaskAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :task_attachments do |t|
      t.references :task, null: false, foreign_key: true
      t.references :uploader, null: false,
        foreign_key: { to_table: :actors }
      t.string :file_path,         null: false  # relative zu BASE_PATH
      t.string :original_filename, null: false
      t.string :content_type
      t.bigint :byte_size
      t.timestamps
    end
    add_index :task_attachments, :file_path
  end
end
