class UnifyPersonsOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :first_name, :string
    add_column :knowledge_items, :last_name,  :string
    add_index  :knowledge_items, :last_name

    # Adapter-Spalte: jeder Contact zeigt auf das KI, das ihn vertritt.
    # Während der Übergangsphase werden beide Welten parallel gepflegt.
    add_column :contacts, :knowledge_item_uuid, :string
    add_index  :contacts, :knowledge_item_uuid, unique: true
  end
end
