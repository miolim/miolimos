# #384 Phase 3a-Hotfix (Hans, 2026-05-27): Reply-KIs sind titel-los
# (`@author · zeit` ist die User-facing-Identifikation). Titel-NOT-
# NULL-Constraint muss raus, sonst kann der Controller nach dem Create
# nicht `title: nil` setzen → Reply landet ohne parent_type/parent_uuid
# in der DB, Stack-Frame zeigt „Content missing".
class AllowNullTitleOnKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    change_column_null :knowledge_items, :title, true
  end
end
