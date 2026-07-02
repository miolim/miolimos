# #602 S1: DER zentrale Sichtbarkeits-Baustein für Inhalte. Ein Modell
# deklariert einmal, WIE es an Topics hängt (Join-Tabelle oder direkte
# topic_id) und wem es "persönlich gehört" — daraus entsteht der
# visible_to(actor)-Scope:
#
#   sichtbar = eigenes Objekt (owner_columns)
#            ∪ hängt an einem für den Actor sichtbaren Topic
#
# Admins und Agenten sind ausgenommen (Actor#visibility_exempt?).
# Objekte OHNE Topic-Verknüpfung sieht nur der Eigentümer ("Privates").
# Die Topic-Sichtbarkeit selbst regelt Topic.visible_to (Mitgliedschaft,
# internal_public, Ersteller).
#
# #602 S2: Dazu der zentrale SCHREIB-Guard — sichtbar heißt nicht
# änderbar. Schreibbar ist ein Objekt für einen Member, wenn es ihm
# gehört (owner_columns) oder an einem Topic hängt, in dem er
# Bearbeiter/Verantwortlicher ist (Topic#writable_by?). Nur-Betrachter
# und intern-Öffentliches ohne Mitgliedschaft: lesen ja, schreiben nein.
# Der Guard sitzt als before_update/before_destroy am Modell — damit ist
# JEDER Web-Schreibpfad abgedeckt (Current.actor; Jobs/Konsole ohne
# Actor und Agenten/Admins passieren ungebremst). update_column/
# update_all umgehen Callbacks bewusst (interne Systempfade).
module VisibleVia
  extend ActiveSupport::Concern

  class_methods do
    # join:          Klassenname der Topic-Join-Tabelle (z.B. "TaskTopic")
    # join_fk:       Spalte der Join-Tabelle, die auf dieses Modell zeigt
    # primary_key:   Schlüssel dieses Modells (:id, bei KIs :uuid)
    # topic_column:  alternativ: direkte FK-Spalte (z.B. :topic_id)
    # owner_columns: Actor-Spalten, die "gehört mir" bedeuten
    def visible_via(join: nil, join_fk: nil, primary_key: :id,
                    topic_column: nil, owner_columns: [:creator_id])
      cfg = { join: join, join_fk: join_fk, primary_key: primary_key,
              topic_column: topic_column, owner_columns: owner_columns }
      class_attribute :visibility_config, instance_writer: false, default: cfg

      scope :visible_to, ->(actor) {
        next all  if actor&.visibility_exempt?
        next none if actor.nil?
        visible_topics = Topic.visible_to(actor).select(:id)
        conds = owner_columns.map { |col| where(col => actor.id) }
        if join
          conds << where(primary_key => join.constantize
                           .where(topic_id: visible_topics).select(join_fk))
        elsif topic_column
          conds << where(topic_column => visible_topics)
        end
        conds.reduce { |a, b| a.or(b) } || none
      }

      before_update  :enforce_visibility_write_guard
      before_destroy :enforce_visibility_write_guard
    end
  end

  # Darf dieser Actor das Objekt ändern/löschen?
  def writable_by?(actor)
    return true if actor.nil? || actor.visibility_exempt?
    cfg = visibility_config
    return true if cfg[:owner_columns].any? { |col| self[col] == actor.id }
    linked_topic_ids =
      if cfg[:join]
        cfg[:join].constantize.where(cfg[:join_fk] => self[cfg[:primary_key]]).pluck(:topic_id)
      elsif cfg[:topic_column]
        [self[cfg[:topic_column]]].compact
      else
        []
      end
    return false if linked_topic_ids.empty?
    Topic.where(id: linked_topic_ids).any? { |t| t.writable_by?(actor) }
  end

  private

  def enforce_visibility_write_guard
    actor = Current.actor
    return if writable_by?(actor)
    raise AccessGate::Unauthorized,
          "#{actor.name} darf #{self.class.name} ##{self[self.class.primary_key]} nicht ändern (nur Betrachter)"
  end
end
