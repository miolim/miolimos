# #480 Increment 3 (Hans, 2026-06-03): Eine Zeile pro Anker, der in einer
# Task-Description steht (8-Hex-Highlight oder 6-stellig-alphanumerischer
# Block-Anker). Pendant zu KnowledgeItemAnchor — befuellt vom Task-Save-Hook
# (TaskAnchors::Sync). Der Wikilink-Resolver nutzt die Tabelle, um
# `[[^anker]]` auf den Task-Absatz aufzuloesen.
class TaskAnchor < ApplicationRecord
  belongs_to :task

  # Gleiche zwei Formate wie KnowledgeItemAnchor (#466): 8-Hex fuer
  # Color-Highlights, 6-stellig alphanumerisch fuer aeltere Block-Anker.
  validates :anchor, presence: true, uniqueness: true,
                     format: { with: /\A(?:[a-f0-9]{8}|[a-z0-9]{6})\z/ }
end
