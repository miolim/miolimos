# #602 S1: Mitgliedschaft eines (menschlichen) Nutzers in einem Topic —
# DIE Freigabe-Einheit für Multi-User. Wer Mitglied ist, sieht das Topic
# und alles, was daran hängt (visible_to-Scopes). Die Rolle beantwortet
# perspektivisch das WIE (viewer = nur lesen) — S1 speichert sie, die
# Schreibrechte-Auswertung folgt in S2.
class TopicMembership < ApplicationRecord
  belongs_to :topic
  belongs_to :actor

  enum :role, { viewer: 0, editor: 1, owner: 2 }, default: :editor

  validates :actor_id, uniqueness: { scope: :topic_id }
end
