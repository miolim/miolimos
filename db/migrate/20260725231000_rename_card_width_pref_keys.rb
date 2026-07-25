# #1152-Aufraeumen: gespeicherte Card-Breiten-Vorlieben auf die Kind-Namen
# umbenennen, unter denen der Blade-Stack sie tatsaechlich nachschlaegt
# (_cardKind in blade_stack_resize.js). Die alten Keys "source"/"list_tasks"/
# "topic_list" waren wirkungslos; "list_default" hatte nie einen Abnehmer.
class RenameCardWidthPrefKeys < ActiveRecord::Migration[8.1]
  RENAMES = {
    "source"     => "src",
    "list_tasks" => "list:tasks",
    "topic_list" => "list:topic"
  }.freeze

  def up
    Actor.where("preferences ? 'card_widths'").find_each do |actor|
      prefs = actor.preferences
      cw    = prefs["card_widths"]
      next unless cw.is_a?(Hash)
      changed = false
      RENAMES.each do |old_key, new_key|
        next unless cw.key?(old_key)
        # Ein bereits unter dem neuen Namen gespeicherter Wert (z.B. per
        # STRG-Doppelklick) gewinnt gegen den alten, wirkungslosen.
        cw[new_key] = cw.delete(old_key) unless cw.key?(new_key)
        cw.delete(old_key)
        changed = true
      end
      changed = true unless cw.delete("list_default").nil?
      actor.update_columns(preferences: prefs) if changed
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
