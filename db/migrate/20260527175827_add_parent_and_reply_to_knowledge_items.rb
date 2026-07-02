# #384 Phase 3a (Hans, 2026-05-27): Reply-KIs als polymorphes
# Beitragssystem. Eine Reply-KI wird einem Eltern-Datensatz angehaengt
# (Task oder KI), hat keinen eigenen Titel und wird per UUID +
# `author + created_at` identifiziert.
#
# Schema:
#   - parent_type    String, nullable. „KnowledgeItem\" | „Task\" | ...
#   - parent_id_int  Bigint, nullable. Eltern mit numerischer id (Task).
#   - parent_uuid    String, nullable. Eltern mit uuid (KnowledgeItem).
#   - published_at   DateTime, nullable. Wie task_comments — Drafts.
#
# Plus neuer enum-Wert :reply (= 11) im item_type-Enum. Reply-KIs
# haben optionale title-Spalte; Model-Validation erlaubt `nil` nur
# fuer item_type=:reply.
class AddParentAndReplyToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    change_table :knowledge_items do |t|
      t.string   :parent_type
      t.bigint   :parent_id_int
      t.string   :parent_uuid
      t.datetime :published_at
    end

    add_index :knowledge_items, [:parent_type, :parent_id_int],
              name: "index_ki_on_parent_int"
    add_index :knowledge_items, [:parent_type, :parent_uuid],
              name: "index_ki_on_parent_uuid"
    add_index :knowledge_items, :published_at,
              name: "index_ki_on_published_at"
  end
end
