class RestructureAwaitingTitleAndDescription < ActiveRecord::Migration[8.1]
  # Awaiting hatte bisher "description" als kurzes Headline-Feld. Das
  # übernimmt jetzt "title" (parallel zu Task). "description" wird als
  # optionales Notizfeld neu angelegt — mehrzeilig, zusätzliche Details.
  def change
    rename_column :awaitings, :description, :title
    add_column    :awaitings, :description, :text
  end
end
