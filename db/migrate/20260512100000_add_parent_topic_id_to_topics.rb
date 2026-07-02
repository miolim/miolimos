class AddParentTopicIdToTopics < ActiveRecord::Migration[8.1]
  # #150: Topics dürfen verschachtelt werden (Marketing → Campagne Q3 →
  # Newsletter). FK auf topics, nullable. Kein Cascade-Delete — wenn ein
  # Parent gelöscht wird, lassen wir die Kinder als Top-Level zurück.
  def change
    add_reference :topics, :parent_topic, foreign_key: { to_table: :topics }, null: true
  end
end
