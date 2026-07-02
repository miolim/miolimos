class CreateKiTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :ki_templates do |t|
      t.string  :name,      null: false           # Anzeigename im Picker
      t.string  :item_type, null: false, default: "note"
      t.string  :title                            # Default-KI-Titel
      t.text    :body                             # Default-KI-Body (Markdown)
      t.timestamps
    end

    add_index :ki_templates, :name
  end
end
