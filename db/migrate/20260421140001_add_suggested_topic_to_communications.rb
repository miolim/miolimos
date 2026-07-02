class AddSuggestedTopicToCommunications < ActiveRecord::Migration[8.1]
  # Phase 6a — Email-Classifier Zustandsfelder.
  # suggested_topic_id        → Klassifikator-Vorschlag (kann nil sein)
  # suggested_topic_score     → Cosine-Similarity [0..1]
  # suggested_topic_decided_at → sobald User übernimmt oder ablehnt
  #   (danach nicht mehr als Vorschlag anzeigen; Re-Runs ignorieren diesen)
  def change
    add_reference :communications, :suggested_topic,
                  foreign_key: { to_table: :topics },
                  null: true
    add_column    :communications, :suggested_topic_score,      :float
    add_column    :communications, :suggested_topic_decided_at, :datetime
  end
end
