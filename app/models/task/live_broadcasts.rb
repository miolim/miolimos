# #564: Live-Broadcasts der Task-Listen — aus task.rb extrahiert (reiner
# Code-Move von #232). UI-Spiegelung gehört nicht zwischen die Domänen-
# Callbacks; hier liegt sie gesammelt und separat testbar.
#
# #232 (Hans, 2026-05-31): GEZIELTE Stream-Updates statt Ganzseiten-Morph.
# Der frueher genutzte broadcast_refresh (Morph) "lief nach" und war
# workflow-behindernd (Hans-Feedback) — er re-rendert die ganze Seite und
# setzt client-seitigen Zustand (Disclosures/Scroll) zurueck. Stattdessen
# ersetzen wir gezielt NUR die Row der Task im "tasks"-Stream. Gezielte
# Stream-Actions loesen KEIN turbo:render/Morph aus -> kein Reset.
# Greift fuer Web- UND API-Schreibzugriffe (Modell-Commit).
#
# Bewusst SYNCHRON (kein broadcast_*_later): die Renders sind klein, und
# inline bleibt die Reihenfolge Controller-Response → Broadcast determinis-
# tisch (wichtig für die idempotenten Remove+Prepend-Sequenzen unten).
class Task < ApplicationRecord
  module LiveBroadcasts
    extend ActiveSupport::Concern

    # Guard auf user-sichtbare Attribute, damit interne Updates keine
    # Broadcast-Welle ausloesen. #232 (2026-06-04): wip_actor_id mit dabei,
    # damit der WIP-Marker live erscheint/verschwindet.
    TASK_LIVE_ATTRS = %w[status priority commitment title assignee_id due_date
                         published_at completed_at deleted_at parent_id
                         wip_actor_id].freeze

    included do
      after_create_commit  :broadcast_task_row_create
      after_update_commit  :broadcast_task_row_update
      after_destroy_commit :broadcast_task_row_remove
    end

    private

    # #232 (Hans, 2026-06-01): Neue Task live in der Assignee-Liste erscheinen
    # lassen — prepend in die passende Sektion. WICHTIG: NICHT auf den globalen
    # "tasks"-Stream, sonst tauchte eine fremde Task in der Liste anderer
    # Nutzer auf — die Liste ist assignee-gefiltert ("tasks_for_<id>").
    # target tasks_section_<key> existiert nur in der Wann-Gruppierung; im
    # Topic-Modus no-op (dort korrigiert sich's beim naechsten Render).
    def broadcast_task_row_create
      return unless visible_in_list?
      broadcast_task_row_insert
    end

    def broadcast_task_row_insert
      broadcast_prepend_to "tasks_for_#{assignee_id}",
        target:  "tasks_section_#{time_section_key}",
        partial: "tasks/row",
        locals:  { task: self, topic: topics.first, show_topic: true,
                   blade_kind: "task", blade_id: id }
    end

    # #602 S2: Empfänger-Streams statt EINEM globalen "tasks"-Stream.
    # Der globale Stream lieferte Row-HTML JEDER Task an JEDE Session —
    # im DOM meist ein No-op (Target fehlt), aber auf der WebSocket-
    # Leitung lesbar. Jetzt: je Nutzer ein privater Stream
    # ("tasks_user_<id>", signiert), beliefert nur, wenn der Nutzer die
    # Task sehen darf. Nutzerzahl ist klein (<10) — der Check pro
    # Empfänger ist eine billige EXISTS-Query.
    def visible_user_streams
      HumanActor.active.select { |u| Task.visible_to(u).where(id: id).exists? }
                .map { |u| "tasks_user_#{u.id}" }
    end

    def broadcast_row_replace_to_recipients
      visible_user_streams.each do |stream|
        broadcast_replace_to stream,
          target:  "task_row_#{id}",
          partial: "tasks/row",
          locals:  { task: self, topic: topics.first, blade_kind: "task", blade_id: id }
      end
    end

    # Remove ist id-only (kein Inhalt) — nach destroy ist die Sichtbarkeit
    # nicht mehr feststellbar, darum an alle Nutzer-Streams.
    def broadcast_row_remove_to_recipients
      HumanActor.active.pluck(:id).each do |uid|
        broadcast_remove_to "tasks_user_#{uid}", target: "task_row_#{id}"
      end
    end

    # #232 (Hans, 2026-05-31): gezielte Row-Replace statt Morph.
    def broadcast_task_row_update
      return if (saved_changes.keys & TASK_LIVE_ATTRS).empty?
      # #232 (2026-06-03): Done-Zustand (und Titel) live in jede offene
      # Detail-Card spiegeln — nur den Header ersetzen, NICHT die editierbare
      # Beschreibung (kein Edit-Verlust). targets (plural) trifft auch
      # mehrfach geoeffnete Karten (#473).
      # #743 (Hans, 2026-06-23): auch wip_actor_id — der grüne WIP-Rahmen der
      # Checkbox sitzt im Header und wurde in der Liste schon live aktualisiert,
      # in einer offenen Card aber nicht. Mit dabei spiegelt sich der Rahmen
      # auch dort sofort, wenn ein Lauf die Aufgabe als WIP markiert/freigibt.
      if saved_change_to_status? || saved_change_to_title? || saved_change_to_wip_actor_id?
        broadcast_replace_to self, targets: "#task_header_#{id}",
          partial: "tasks/detail_header", locals: { task: self }
        # #892 (Hans): Das Spine-Status-Icon (WIP orange / erledigt grünes
        # square-check) sitzt AUSSERHALB des Headers und wurde bisher nur beim
        # Reload aktualisiert. Hier gezielt mit-ersetzen, damit es live umspringt.
        broadcast_replace_to self, targets: "#task_spine_#{id}",
          partial: "tasks/spine", locals: { task: self }
      end
      # #232 (2026-06-01): Reopen/Publish/Undiscard -> Row war versteckt,
      # jetzt sichtbar: in die Assignee-Liste (re)inserten. Remove+Prepend
      # ist idempotent (kein Duplikat).
      if became_visible?
        broadcast_remove_to "tasks_for_#{assignee_id}", target: "task_row_#{id}"
        broadcast_task_row_insert
        return
      end
      # #232 (2026-05-31): Zaehler-Liveness ohne Server-Roundtrip — verlaesst
      # die Task die offene Liste, Row gezielt entfernen (list-count zaehlt
      # per MutationObserver runter); sonst Row in-place ersetzen.
      if done? || discarded? || draft?
        broadcast_row_remove_to_recipients
      else
        broadcast_row_replace_to_recipients
      end
    end

    def broadcast_task_row_remove
      broadcast_row_remove_to_recipients
    end

    # Erscheint die Task als eigene Top-Level-Row in der Aufgabenliste?
    # Spiegelt TaskQuery#relation + die Section-Logik.
    def visible_in_list?
      !done? && !draft? && !discarded? && parent_id.nil? && assignee_id.present?
    end

    # War die Task VOR diesem Save unsichtbar und ist jetzt sichtbar?
    # (Reopen done->open, Publish, Undiscard.) Dann muss die Row in fremden
    # Sessions neu eingefuegt werden (Replace liefe ins Leere).
    def became_visible?
      return false unless visible_in_list?
      prev_status    = saved_change_to_status?       ? saved_changes["status"].first       : status
      prev_published = saved_change_to_published_at? ? saved_changes["published_at"].first : published_at
      prev_deleted   = saved_change_to_deleted_at?   ? saved_changes["deleted_at"].first   : deleted_at
      was_visible = prev_status.to_s == "open" && !prev_published.nil? &&
                    prev_deleted.nil? && parent_id.nil? && assignee_id.present?
      !was_visible
    end
  end
end
