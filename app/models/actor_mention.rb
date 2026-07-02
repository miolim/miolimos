# #384 Phase 2 (Hans, 2026-05-27): Adressierungs-Mention KI -> Actor.
# Wird beim KI-Save aus @-Mentions im Body extrahiert (siehe
# KnowledgeMarkdown::ActorMentions). Anders als KnowledgeItemMention
# (KI -> KI fuer Wikilink-Backlinks) verweist hier eine KI auf einen
# Actor, der eingeloggt + per Inbox angesprochen werden kann.
class ActorMention < ApplicationRecord
  belongs_to :knowledge_item,
    foreign_key: :knowledge_item_uuid, primary_key: :uuid
  belongs_to :actor

  validates :knowledge_item_uuid, uniqueness: { scope: :actor_id }
end
