class CreateSettings < ActiveRecord::Migration[8.1]
  # Generische Key/Value-Settings — bisher gab's keine, weil alles
  # entweder per ENV oder Code-Konstante geregelt war. Erste Anwendung:
  # editierbares Chat-Import-Prompt-Template.
  def change
    create_table :settings do |t|
      t.string :key,   null: false
      t.text   :value
      t.timestamps
    end
    add_index :settings, :key, unique: true
  end
end
