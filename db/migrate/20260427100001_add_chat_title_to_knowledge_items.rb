class AddChatTitleToKnowledgeItems < ActiveRecord::Migration[8.1]
  # Externe Identität für KI-Chats: chat_title ist der unveränderte
  # Chat-Titel aus der KI-Plattform (Claude/ChatGPT/…). Match-Schlüssel
  # für den Append-Workflow — bleibt fix, auch wenn der User in
  # miolimOS den title nachträglich umbenennt. Indexed für Lookup.
  def change
    add_column :knowledge_items, :chat_title, :string
    add_index  :knowledge_items, :chat_title
  end
end
