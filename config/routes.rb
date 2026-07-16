Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ─── Auth ──────────────────────────────────────────────────────────────
  get    "/login",  to: "sessions#new",     as: :login
  post   "/login",  to: "sessions#create"
  # #816: geräteübergreifender Stack-Verlauf (Drawer-Sync).
  resources :stack_snapshots, only: [:index, :create, :update, :destroy]

  # #806: First-Run-Onboarding — nur erreichbar solange kein HumanActor existiert.
  get    "/setup",  to: "setup#new",        as: :setup
  post   "/setup",  to: "setup#create"
  delete "/logout", to: "sessions#destroy", as: :logout

  # ─── Web-UI ────────────────────────────────────────────────────────────
  root to: redirect("/dashboard")

  # #532 Phase 2: Theme-Werkbank für Dokument-Vorlagen.
  get "documents/preview", to: "documents#preview", as: :document_preview
  get "documents/pdf",     to: "documents#pdf",     as: :document_pdf
  # #532 (2026-06-08): Document-Entität — Liste + Detail-Blades + Render.
  # NACH den Literal-Routes, damit /documents/preview|pdf nicht als :id matchen.
  resources :documents, only: [:index, :show, :create, :update, :destroy] do
    member do
      post   :restore                          # #787: aus dem Papierkorb holen
      delete "artifacts/:artifact_id", action: :destroy_artifact, as: :destroy_artifact  # #787: finalen PDF-Stand löschen
      get   :card                              # Detail-Blade
      get   :pdf, action: :show_pdf, as: :rendered_pdf
      get   :signed_pdf                        # #547: AES-signiertes PDF
      post  :archive_pdf                       # #532: finalen Stand festschreiben
      post  :toggle_artifact_share             # #536: Portal-Freigabe je Stand
      get   "artifacts/:artifact_id", action: :artifact, as: :artifact  # #532: Stand ausliefern
      post  :link                              # #532: Verknüpfung (Picker) setzen/lösen
      post  :create_body_ki                    # #532: Text-KI anlegen + verknüpfen
      patch :document_fields                   # #532: freie Key-Value-Felder
      patch :select_identifiers                # #532: Empfänger-IDs an/abwählen
      post   :franking                         # #995: Internetmarke/Dummy setzen
      delete :franking, action: :destroy_franking, as: nil
    end
    collection do
      get :list_card                           # Listen-Blade (Sidebar/Stack)
      get :suggest_links                       # #532: Picker-Vorschläge (JSON)
      get :trash                               # #787: Papierkorb (gelöschte Dokumente)
    end
  end

  # #926 (Hans, 2026-07-09): Rechnung/Angebot als eigene Entität — gleiche
  # Verfahren-Routen wie documents (PrintableResource) + Positionen/e-Rechnung.
  resources :invoices, only: [:index, :show, :create, :update, :destroy] do
    member do
      post   :restore
      delete "artifacts/:artifact_id", action: :destroy_artifact, as: :destroy_artifact
      get   :card
      get   :pdf, action: :show_pdf, as: :rendered_pdf
      get   :signed_pdf
      get   :zugferd_pdf                       # #541: ZUGFeRD-PDF/A-3
      get   :xrechnung_xml                     # #541: XRechnung-XML
      post  :archive_pdf
      post  :upload_artifact                   # #964: Beleg (PDF) manuell anhängen — nur eingehend
      post  :toggle_artifact_share
      get   "artifacts/:artifact_id", action: :artifact, as: :artifact
      post  :link
      patch :document_fields
      patch :select_identifiers
      patch :invoice_lines                     # #541: Rechnungspositionen (Inline-Upsert, Legacy)
      post  :import_time_entries               # #541: Zeitbuchungen übernehmen
      post  :add_invoice_line                  # #541: neue (leere) Position anlegen
      post   :franking                         # #995: Internetmarke/Dummy setzen
      delete :franking, action: :destroy_franking, as: nil
    end
    collection do
      get :list_card
      get :suggest_links
      get :trash
    end
  end

  # #541 (Hans, 2026-06-09): Rechnungsposition als eigenes Detail-Blade —
  # Felder bearbeiten + Zeitbuchungen zuordnen/lösen.
  resources :invoice_lines, only: [] do
    member do
      get    :card
      patch  :update, action: :update_line
      post   :assign_time
      delete :unassign_time
    end
  end

  # #533 Phase 1b/#2: Zeitbuchung (Header-Timer / Card-Buttons / Quick-Add /
  # Pause+mehrere Timer).
  resources :time_entries, only: [:index, :create, :destroy] do
    member do
      get  :card           # #2b: Detail-Blade einer Buchung (Ereignis-Log)
      patch :update_times  # #3/#4: Start/Ende bzw. Dauer bearbeiten
      patch :set_billable  # #541: Buchung als abrechenbar markieren/zurücknehmen
      post :pause
      post :resume
      post :finish
    end
    collection do
      post :stop
      post :reply_start    # #1: Auto-Timer beim Antwort-Bearbeiten starten/fortsetzen
      post :reply_end      # #1: beim Abschließen beenden
      post :reply_pause    # #588: Fokus-Verlust pausiert den Auto-Timer
      get  :running
      get  :list_card      # #557: Zeiten-Liste als anhängbares Stack-Blade
    end
  end
  get "/dashboard", to: "dashboard#index", as: :dashboard
  # #625 (Hans, 2026-06-14): Überweisungs-Formular → GiroCode (EPC069-12).
  get  "/ueberweisung",      to: "giro_codes#show",      as: :giro_code
  # #625 (Hans, 2026-06-15): IBAN direkt am Kontakt hinterlegen.
  post "/ueberweisung/iban", to: "giro_codes#save_iban", as: :giro_code_save_iban
  # #434 (Hans, 2026-06-01): Standalone-Card des list:dashboard-Blades —
  # damit der Stack-Restore (Verlauf-Drawer) das erste Blade wieder
  # aufbauen kann (analog zu /tasks/list_card etc.). Vorher fehlte als
  # einzigem list:-Typ der Endpoint, der Restore-Fetch lief in 404.
  get "/dashboard/list_card", to: "dashboard#list_card", as: :dashboard_list_card
  # #393 (Hans, 2026-05-28): Bulk-Mark-as-read fuer alle ungelesenen
  # Reply-KIs der angegebenen Tasks. Setzt einen ActorView-Stempel pro
  # Task, sodass das Dashboard sie nicht mehr als unread zaehlt.
  post "/dashboard/mark_read", to: "dashboard#mark_read", as: :dashboard_mark_read
  # #387 Phase B (Hans, 2026-05-28): Backlink-Count fuer einen
  # Highlight-Anker. Counter im Right-Click-Menue zaehlt KIs+Tasks,
  # die `[[^id]]` in ihrem Body erwaehnen.
  get "/highlights/:anchor/backlinks_count", to: "highlights#backlinks_count",
      as: :highlight_backlinks_count, constraints: { anchor: /[a-f0-9]{8}/ }
  # #387 Phase 2 (Hans, 2026-05-30): Tag-Editor-Endpoints.
  get   "/highlights/:anchor/tags", to: "highlights#tags",
        as: :highlight_tags, constraints: { anchor: /[a-f0-9]{8}/ }
  patch "/highlights/:anchor/tags", to: "highlights#update_tags",
        constraints: { anchor: /[a-f0-9]{8}/ }

  # Manueller Builder-Inbox-Trigger aus dem Dashboard. Setzt
  # actors.inbox_run_requested_at auf jetzt; mein Cron-Tick liest
  # das Flag im Heartbeat-Endpoint und arbeitet die Inbox sofort ab.
  post "/builders/:id/request_inbox_run",
       to: "builder_triggers#create",
       as: :request_inbox_run

  resources :topics, param: :slug do
    collection do
      get :suggest
      # #435 (Hans, 2026-06-01): Listen-Blade ueber ALLE Topics (analog
      # tags/list_card). /topics/list_card -> topics#topics_list_card.
      get :list_card, action: :topics_list_card, as: :all_list_card
    end
    member do
      # #567: Topic-Eigenschaften als Blade im aktuellen Stack.
      get  :properties_card
      # #571: Portal des Projekts aus Kundensicht öffnen.
      get  :portal_preview
      # #573 v2: Kalender-Reiter-Frame (Monats-/Wochen-Navigation in-place).
      get  :calendar_tab
      # #566: Kunde (Person/Org-KI) zuordnen/lösen — value leer = lösen.
      post :set_customer
      post :instantiate
      post :reorder_tasks
      # #494 (Hans, 2026-06-03): „Quelle aufnehmen" — neue Quelle anlegen + zuordnen.
      post :create_source
      # /topics/:slug/next_step als Singleton — POST setzt, DELETE leert.
      post   :set_next_step,   path: "next_step"
      delete :clear_next_step, path: "next_step"
      # #196: Detail-Pane für die History-Page.
      get :detail_pane
      # #163 Phase 4: Blade-Card-Fragment fuer Cross-Entity-Stack.
      get :card
      # #247: Listen-Blade fuer Topic — Aufgaben des Topics als Liste.
      get :list_card
      # #325 Phase 3a: Work-Tree-Render-Vorschau.
      get :render_preview
      # #352 (Hans, 2026-05-25): Rendering-Blade-Fragment fuer den Stack.
      get :render_card
      # #352-follow: Reference-Blade fuer den kompletten Topic-Work-Tree.
      get :refs_card
    end
    # #325 (Hans, 2026-05-24): Work-Tree-CRUD pro Topic.
    resources :work_nodes, only: [:create, :update, :destroy] do
      member do
        post :indent
        post :outdent
      end
    end
    # #592: Bäume anlegen (Linsen-Modell — Work-Tree + Zweckgeflecht
    # sind Sichten auf dieselben TopicTrees).
    resources :trees, only: [:create, :destroy], controller: "topic_trees"
  end

  # #592 Z2: Fokusansicht — Blade auf einen Baum-Knoten (Cursor im
  # Geflecht). :id = Einstiegs-Knoten (Blade-Identität), ?focus= = aktuell
  # fokussierter Knoten (In-Frame-Navigation).
  get "tree_focus/:id/card", to: "tree_focus#card", as: :tree_focus_card

  # #299: Task-Vorlagen-Picker fuer den Quickadd. Vor `resources :tasks`,
  # damit GET /task_templates/suggest nicht von /tasks/:id geschluckt
  # wird.
  resources :task_templates, only: [] do
    collection do
      get :suggest
    end
  end
  # #301: KI-Vorlagen-Picker fuer den KI-Quick-Create-Slot.
  resources :ki_templates, only: [] do
    collection do
      get :suggest
    end
  end

  resources :tasks do
    collection do
      get :suggest
      get :suggest_tags   # #162: existierende Tags für Picker-Vorschläge
      get :trash
      # #163 Phase 5a-2: Listen-Blade-Card fuer Sidebar-Plus-Append.
      get :list_card
      # #388 (Hans, 2026-05-28): Batch-Edit von Tasks. ids[] + Aenderungen.
      post :bulk_update
    end
    member do
      post :toggle_done
      post :toggle_milestone   # #572: Meilenstein-Flag (Portal-Roadmap)
      post :create_awaiting   # "Warte auf Ergebnis"
      post :set_commitment    # Heute/Demnächst/Später/Eingang setzen
      post :restore           # Soft-Delete rückgängig
      post :promote_to_topic  # #150 Phase B
      post :publish           # #167: Entwurf veröffentlichen
      post :unpublish         # #411 (Hans, 2026-05-30): published Aufgabe pausieren
      get  :card              # #163 Phase 2: Blade-Card-Fragment fuer Cross-Entity-Stack
      get  :ref_label         # #534: JSON {found,id,title} für CM6 [[#id]]-Pille
      post :wrap_highlight     # #480 Inc.2: Highlight in der Task-Description
      post :wrap_person        # #655: Selektion als Personen-Wikilink
      # #480 Inc.3: Absatz-Aktionen an der Task-Description (wie KI-Body).
      post :ensure_anchor      # Block-Anker stabilisieren
      post :comment_at         # Kommentar an einem Absatz
      post :task_at            # Aufgabe an einem Absatz
    end
    resources :topics, only: [:create, :destroy], controller: "task_topics"
    # #162: Tags-Picker als nested resource. ID-Param ist das Tag-Wort
    # selbst (URL-encoded) — Tags sind kein eigenes Model, sondern eine
    # `string[]`-Spalte auf tasks.
    resources :tags, only: [:create, :destroy], controller: "task_tags",
              param: :tag, constraints: { tag: /[^\/]+/ }
    resources :mentions, only: [:create, :destroy], controller: "task_mentions"
    resources :sources, only: [:create, :destroy], controller: "task_sources"
    resources :dependencies, only: [:create, :destroy], controller: "task_dependencies"
    resources :subtasks, only: [:create, :destroy], controller: "task_subtasks"
    resources :comments, only: [:create, :show, :edit, :update, :destroy], controller: "task_comments" do
      member do
        post :publish   # #167: Entwurfs-Kommentar veröffentlichen
      end
    end
    # #384 Phase 3b (Hans, 2026-05-27): Reply-KIs an einer Task.
    # #232 (Hans, 2026-06-01): :index liefert das Replies-Listen-Frame-Fragment
    # fuer gezielte Live-Reloads (turbo-frame src).
    resources :replies, only: [:index, :create, :update, :destroy], controller: "task_replies", param: :id
    resources :attachments, only: [:create, :show, :destroy], controller: "task_attachments"
  end

  resources :awaitings do
    collection do
      get :list_card     # #163 Phase 5a-2: Listen-Blade fuer Cross-Entity-Stack
    end
    member do
      post :resolve
      post :create_task
      get  :card         # #163 Phase 5b-1: Detail-Blade-Card-Fragment
    end
    resources :topics, only: [:create, :destroy], controller: "awaiting_topics"
  end

  # #211: Dashboard-Unread-Liste hat pro Eintrag + pro Sektion einen
  # "Als gelesen markieren"-Button. Single-Comment via comment_id,
  # Bulk via comment_ids[].
  resources :comment_reads, only: [:create]

  # /contacts → Personen/Orgs sind jetzt KIs, Liste lebt unter
  # /knowledge_items?type=person+organization. Alt-URLs werden umgeleitet.
  get "/contacts",      to: redirect("/knowledge_items?item_type=person")
  get "/contacts/:id",  to: redirect("/knowledge_items?item_type=person")
  # #257 follow-up: Listen-Blade fuers Sidebar-Plus an „Personen".
  # Konvention `/:list/list_card` wie tasks/awaitings/… — der
  # blade-stack-Controller mappt kind:list,id:persons hierher.
  get "/persons/list_card", to: "knowledge_items#persons_list_card", as: :list_card_persons

  resources :communications, only: [:index, :show, :destroy] do
    collection do
      post :classify_all    # Batch-Klassifikation aller Mails ohne Thema
      get  :list_card       # #163 Phase 5a-2: Listen-Blade fuer Cross-Entity-Stack
      # #1018 (Hans, 2026-07-16): Batch-Edit — ids[] + Thema zuordnen/loeschen.
      post :bulk_update
    end
    resources :topics, only: [:create, :destroy], controller: "communication_topics"
    # #695: Tags (string[]-Spalte, analog task_tags).
    resources :tags, only: [:create, :destroy], controller: "communication_tags",
              param: :tag, constraints: { tag: /[^\/]+/ }
    # #633: E-Mail-Anhang in die Inbox übernehmen (?index=N).
    post "attachments/import", to: "communications/attachments#create", as: :import_attachment
    member do
      post :create_task
      post :create_awaiting   # "Warte auf Antwort"
      post :accept_topic_suggestion
      post :reject_topic_suggestion
      get  :card              # #163 Phase 5b-1: Detail-Blade-Card-Fragment
      patch :call_duration    # #765: Anrufdauer nachträglich setzen/ändern
    end
  end

  # #191: persönliche „📌 Gepinnt"-Liste — Stack-View über alle für
  # current_actor gepinnten KIs. Gleicher Layout wie /knowledge_items.
  # #203 Phase E.1: lebt jetzt in KnowledgeStackController.
  # #384 Phase 2 (Hans, 2026-05-27): Actor-Suggest fuer @-Mention-Autocomplete.
  get "/actor_suggests", to: "actor_suggests#index", as: :actor_suggests

  get "/pinned", to: "knowledge_stack#pinned", as: :pinned
  # #163 Phase 5a-3: Listen-Blade fuer Cross-Entity-Stack.
  get "/pinned/list_card", to: "knowledge_stack#pinned_list_card", as: :list_card_pinned

  resources :knowledge_items, param: :uuid, only: [:index, :show, :create, :new, :edit, :update, :destroy] do
    collection do
      # #609: Editor-Paste-Upload (Bild aus Zwischenablage -> Bild-KI).
      post :paste_image
      get  :suggest
      # #363 (Hans, 2026-05-25): KI-Tags-Picker-Suggestions analog Tasks.
      get  :suggest_tags
      get  :trash
      get  :list_card         # #257: Listen-Blade fuers Sidebar-Plus
      post :wikilink_create   # [[Neuer Name]]-Klick legt KI an
      post :resolve           # UUID → {title, item_type} für History-Drawer
    end
    member do
      # #608: Bekanntheit manuell togglen (grünes Icon).
      post :toggle_personally_known
      # #705 (Hans): Body als HTML/Markdown rendern umschalten.
      post :toggle_render_mode
      post :restore
      # #544: ID-Nummern (Kundennummer etc.) am Person/Org-KI speichern.
      patch :identifiers
      patch :addresses          # #532: strukturierte Postadressen
      patch :bank_accounts      # #786: Bankverbindungen
      patch :vat_exempt         # #541: USt-Befreiung am Kontakt (DB-direkt)
      post  :complete_from_url  # #761: Kontaktdaten aus einer URL extrahieren
      # #203 Phase E.1: card, toggle_pin, detail_pane wandern zu
      # KnowledgeStackController; URL-Pfade bleiben identisch.
      get  :card,        to: "knowledge_stack#card"
      # #343 (Hans, 2026-05-25): Reference-Blade — Wikilink-Ziele der KI.
      get  :refs_card,   to: "knowledge_stack#refs_card"
      # #365 Phase 3 (Hans, 2026-05-25): Color-Wrap (Absatz/Selektion).
      # #378 Phase 3 (Hans, 2026-05-26): Action in eigenen
      # KnowledgeHighlightsController ausgelagert; URL bleibt stabil.
      post :wrap_highlight, to: "knowledge_highlights#wrap"
      post :wrap_person,    to: "knowledge_highlights#wrap_person"   # #655
      post :toggle_pin,  to: "knowledge_stack#toggle_pin"
      get  :detail_pane, to: "knowledge_stack#detail_pane"
      # #460 (Hans, 2026-06-04): Supersession setzen/aufheben (Achse B).
      post   :supersede     # successor_uuid → dieses KI als abgelöst markieren
      delete :supersede, action: :unsupersede
      get  :file           # Binär-Datei (PDF etc.) inline streamen
      post :quote_from_clipboard  # Markierten Text aus PDF in Quotes-Sammlung legen
      # #155: Bulk-Trigger für Entity-Import; legt einen Task für den
      # Researcher-Agent an mit Liste der fehlenden [[Title|URL]]-
      # Wikilinks im KI-Content.
      # #378 Phase 4 (Hans, 2026-05-26): Action in
      # KnowledgeWikilinkResearchController ausgelagert; URL bleibt stabil.
      post :request_entity_import,   to: "knowledge_wikilink_research#request_entity_import"
      # #183: Per-Wikilink-Recherche-Trigger; legt EINEN Task pro
      # [[Title|URL]]-Wikilink an.
      post :start_wikilink_research, to: "knowledge_wikilink_research#start_wikilink_research"
    end

    # Block-Anchor-Operationen (eigener Controller, #127). URL-Pfade
    # bleiben stabil, nur die Klasse hat sich verschoben.
    member do
      post :ensure_anchor,     to: "knowledge_anchors#create",   as: :ensure_anchor
      post :comment_at,        to: "knowledge_anchors#comment",  as: :comment_at
      # #467 (Hans, 2026-06-02): Aufgabe an einem Anker erzeugen — die
      # Beschreibung traegt einen Wikilink auf den Anker.
      post :task_at,           to: "knowledge_anchors#task",     as: :task_at
      post :start_research_at, to: "knowledge_anchors#research", as: :start_research_at
      get  :backlinks,         to: "knowledge_anchors#backlinks"
    end

    # #384 Phase 3a (Hans, 2026-05-27): Dialog-Replies an einer KI.
    # #232 (Hans, 2026-06-01): :index liefert das Replies-Listen-Frame-Fragment
    # fuer gezielte Live-Reloads (turbo-frame src).
    resources :replies, only: [:index, :create, :update, :destroy], controller: "knowledge_replies", param: :id

    # Versionshistorie (eigener Controller, #127). URL-Pfade bleiben
    # stabil, Helper-Namen ebenso (history_knowledge_item_path etc.).
    member do
      get  :history,         to: "knowledge_versions#index"
      get  :version,         to: "knowledge_versions#show"
      post :restore_version, to: "knowledge_versions#restore"
    end
    resources :topics,   only: [:create, :destroy], controller: "knowledge_topics"
    resources :mentions, only: [:create, :destroy], controller: "knowledge_mentions"
    resources :task_mentions, only: [:create, :destroy], controller: "knowledge_task_mentions"
    # #363 (Hans, 2026-05-25): KI-Tags-Picker — analog task_tags.
    resources :tags, only: [:create, :destroy], controller: "knowledge_item_tags",
      param: :tag, constraints: { tag: %r{[^/]+} }

    # #239 Phase B: typed Relations werden ueber den source-KI + anchor_id
    # adressiert. GET liefert die aktuelle Relation als JSON, PATCH
    # aktualisiert Label/Description/Direction/Provenance.
    resources :relations, only: [:show, :update], param: :anchor_id do
      collection do
        # #239 Phase B+: Auto-Typify — fuegt ^anchor in den Nten Wikilink.
        post :typify
      end
    end
  end

  # Bibliographische Quellen
  resources :sources, param: :slug do
    collection do
      get :suggest
      get :list_card  # #163 Phase 5a-2: Listen-Blade fuer Cross-Entity-Stack
    end
    member do
      get :card  # Card-Fragment für den Sliding-Pane-Stack
    end
    # #494 (Hans, 2026-06-03): Web-UI fuer Quelle↔Thema + Relevanz + Notiz
    # (bisher nur API). :id = topic_id. Antwort: turbo_stream.
    resources :topics, only: [:create, :update, :destroy],
              controller: "source_topics"
  end

  # Prompt-Templates für AiTransform-Processor
  resources :prompt_templates, param: :slug

  # Inbox / Triage-Layer
  # #618 v2: Alias für die generische Listen-Blade-Konvention
  # (/:resource/list_card) — die Resource heißt inbox_items, der Pfad inbox.
  get "inbox_items/list_card", to: "inbox_items#list_card"

  resources :inbox_items, path: "inbox", only: [:index, :show, :create, :update, :destroy] do
    member do
      post :process_now,  path: "process"
      post :archive
      get  :poll
      get  :card    # #618: Detail-Blade
    end
    collection do
      post :scan
      get  :list_card     # #163 Phase 5a-2: Listen-Blade fuer Cross-Entity-Stack
    end
    # #171: Themen-Picker auf dem Inbox-Detail.
    resources :topics, only: [:create, :destroy], controller: "inbox_item_topics"
  end

  # #160: User-History — Tracker-POST und History-Page.
  resources :actor_views, only: [:create]
  get "/history", to: "history#index", as: :history
  # #163 Phase 5a-3: Listen-Blade fuer Cross-Entity-Stack.
  get "/history/list_card", to: "history#list_card", as: :list_card_history
  get "/history/more",      to: "history#more",      as: :more_history   # #631 v2

  # #634: PWA-Share-Target (Android-Teilen-Menü) → Inbox.
  post "/share", to: "shares#create"
  get  "/share", to: "shares#show"

  # Globale Suche
  get "/search", to: "search#index", as: :search

  # Einstellungen
  get "/settings", to: "settings#index", as: :settings
  # #613: Einstellungen als Blade-Stack — Listen-Card + Seiten-Cards.
  get "settings/list_card",   to: "settings/blades#list_card", as: :settings_list_card
  get "settings/blade/:page", to: "settings/blades#card",      as: :settings_blade
  # #613 Stufe 2: Unterseiten-Blades (sub: "new" | "<id>" | "<id>:edit").
  get "settings/blade/:page/sub/:sub", to: "settings/blades#sub_card", as: :settings_sub_blade
  # #602 S3: „Als X ansehen" — Read-only-Vorschau (Admin).
  post   "settings/users/:id/preview", to: "preview_sessions#create",  as: :start_preview
  delete "preview",                    to: "preview_sessions#destroy", as: :end_preview

  namespace :settings do
    resources :accounts, only: [:index, :destroy] do
      collection do
        get :connect
        get :callback
        patch :sync_policy   # #768: globale Mail-Sync-Policy (intern ein/aus)
      end
      member do
        post :sync
        # #573-Folge: Kalender-ID am Konto pflegen.
        patch :update_settings
      end
    end
    resources :users
    resources :agents do
      member do
        post :regenerate_token
        post :trigger_inbox_run
      end
    end
    # #271: Vorlieben des Actors (Card-Breiten, Wheel-Speed, Sidebar-Klick).
    resource :preferences, only: [:show, :update], controller: "preferences"
    # #547: Unterschriftsbild des Users (fürs signierte PDF).
    resource :signature, only: [:show, :update, :destroy], controller: "signatures"
    # #995: Internetmarke-Zugangsdaten (Portokasse/DHL-API) fürs Frankieren.
    resource :internetmarke, only: [:show, :update, :destroy], controller: "internetmarke" do
      post :test
    end
    resources :teams, only: [:index]
    resources :templates, only: [:index]
    # #299: Task-Vorlagen — Builder-Konfig fuer den Quickadd-Picker.
    resources :task_templates, except: [:show]
    # #301: KI-Vorlagen — Konfig fuer den KI-Quick-Create-Picker.
    resources :ki_templates, except: [:show]
    # #239 Phase C: Uebersicht der typed-Wikilink-Labels (Beziehungstypen).
    # Phase D: zusaetzlich CRUD fuer das RelationType-Vokabular.
    resources :relations, only: [:index, :create, :update, :destroy]
    resources :llm_activities, only: [:index, :show] do
      member do
        post :retry
      end
    end

    get   :knowledge_import,        to: "knowledge_import#index"
    patch :knowledge_import_prompt, to: "knowledge_import#update_prompt"
    post  :knowledge_import_prompt_reset, to: "knowledge_import#reset_prompt"
    patch :research_prompt,         to: "knowledge_import#update_research_prompt"   # #672
    post  :research_prompt_reset,   to: "knowledge_import#reset_research_prompt"
    post  :knowledge_import_run,    to: "knowledge_import#run_import"

    # #417 (Hans, 2026-05-30): Tag→Lucide-Icon-Mapping.
    get   :tag_icons, to: "tag_icons#index"
    patch :tag_icons, to: "tag_icons#update"
  end

  # #434 Teil 2 (Hans, 2026-06-01): generischer Stack-ID -> Label-Resolver
  # fuer den Verlauf-Drawer (alle Stack-Typen, nicht nur KIs).
  post "stack/resolve", to: "stack#resolve", as: :stack_resolve

  # #456 (Hans, 2026-06-02): /tags als vollwertige Blade-Stack-Seite.
  get "tags",                 to: "tags#index", as: :tags
  # #418 (Hans, 2026-05-30): Tag-Listen-Blades.
  # Order matters: `/tags/list_card` (alle Tags) zuerst, bevor die
  # dynamische `:tag`-Route greift.
  get "tags/list_card",       to: "tags#tags_list_card", as: :tags_list_card
  get "tags/:tag/list_card",  to: "tags#list_card", as: :tag_list_card,
      constraints: { tag: %r{[^/]+} }
  # #428 Phase 4 (Hans, 2026-05-31): Farbe/Beschreibung eines Tags pflegen.
  patch "tags/:tag",          to: "tags#update", as: :tag_update,
      constraints: { tag: %r{[^/]+} }

  # ─── API bleibt wie Phase 3 ────────────────────────────────────────────
  namespace :api do
    namespace :v1 do
      # /api/v1/contacts → Person/Org-KIs werden über knowledge_items
      # ausgeliefert. Alt-Endpunkt antwortet mit 410 Gone.
      match "contacts(/*path)", to: "contacts#gone", via: :all

      resources :topics do
        member do
          post :instantiate
        end
      end

      resources :tasks do
        resources :topics,   only: [:create, :destroy], controller: "task_topics"
        resources :comments, only: [:create],           controller: "task_comments"
        # #182: Bearer-Auth-Stream für Task-Anhänge, damit Agenten via
        # WebFetch Screenshots/PDFs lesen können. #774: + create (Upload).
        resources :attachments, only: [:show, :create], controller: "task_attachments"
      end

      resources :awaitings do
        member do
          post :resolve
          post :create_task
        end
      end

      resources :communications, only: [:index, :show] do
        resources :topics, only: [:create, :destroy], controller: "communication_topics"
      end

      resources :knowledge_items, param: :uuid, only: [:index, :show, :create, :update, :destroy] do
        collection do
          post :append   # Append-Session-Endpoint für Chat-Workflow
        end
        member do
          get :content
          # #460 (Hans, 2026-06-04): Edit-Historie (git) über die API
          # lesbar/restaurierbar — Achse A der Versionierung.
          get  :history
          get  :version          # ?sha=… → Body einer früheren Fassung
          post :restore_version  # {sha:…} → alte Fassung als neuer Commit
          # #516 (Hans, 2026-06-05): zwei Personen-KIs zusammenführen
          # (Quellen-Autorschaft umhängen + Dublette ablösen).
          post :merge_into       # {target_uuid:…}
        end
        # #155 Schritt 1: typed Wikilink-Relations via API — der
        # Researcher pflegt Label/Beschreibung/Richtung/Provenance.
        resources :relations, only: [:index, :show, :update], param: :anchor_id
        # #460 (Hans, 2026-06-04): Diskussion-Beitrag (Reply-KI) an einem
        # KI — das KI-Pendant zu /tasks/:id/comments.
        resources :replies, only: [:create], controller: "knowledge_replies"
      end

      # #155 Phase 3: Bibliographische Quellen via API. Schlank — title +
      # ein paar CSL-Kernfelder, mehr lässt sich nachreichen.
      # #460: update ergänzt — Metadaten nachpflegen.
      resources :sources, param: :slug, only: [:index, :show, :create, :update] do
        # #155 Phase 5c: Source ↔ Recherche-Topic mit Relevanz-Markierung.
        resources :topics, only: [:index, :create, :update, :destroy],
                  controller: "source_topics"
        # #516 (Hans, 2026-06-05): Autor-Verknüpfung identifizieren/umhängen.
        resources :creators, only: [:update], controller: "source_creators"
      end

      # Inbox-Ingress per API — wird vom Browser-Add-on und ähnlichen
      # Clients genutzt (POST mit source_url + optional title/text).
      resources :inbox_items, only: [:create, :index, :show]

      # #183: Researcher patcht den Job, sobald die recherchierte KI
      # angelegt ist — Wikilinks rendern dann grün statt ⏳.
      resources :wikilink_research_jobs, only: [:update]

      # Heartbeat: der miolim_builder ruft den Endpoint regelmäßig auf,
      # damit das Dashboard "aktiv vor X min" anzeigen kann. Optional
      # auch von einem OS-Cron als Watchdog: wenn last_seen_at zu alt,
      # weiß der Server, dass der Builder hängt.
      post  "heartbeat", to: "heartbeats#create"
      get   "heartbeat", to: "heartbeats#show"
      # #518 (Hans, 2026-06-05): offene KI-Diskussions-Mentions des Agenten.
      get   "mentions",  to: "heartbeats#mentions"
    end
  end
  # #536 P3: Hans' Antwort in den Portal-Thread (aus der Communication-Detail).
  resources :communications, only: [] do
    resources :portal_replies, only: [ :create ]
  end

  # #536: interne Verwaltung der Portal-Zugänge (Topic-Blade).
  resources :topics, only: [] do
    resources :portal_accesses, only: [ :create ]
    get "portal_export", to: "portal_accesses#export"   # #536 P4: Übergabe-ZIP
    # #602 S1: Topic-Mitglieder (Eigenschaften-Blade) + Sichtbarkeit.
    resources :memberships, only: [ :create, :update, :destroy ],
              controller: "topic_memberships"
    patch "visibility", to: "topic_memberships#set_visibility"
  end
  resources :portal_accesses, only: [ :update ] do
    member { post :send_link }   # #570: Magic-Link explizit verschicken
  end

  # ── #573: Kalender — Misch-Ansicht aller Zeitobjekte + Erfassung + ICS. ──
  get  "calendar",            to: "calendar#index"
  get  "calendar/list_card",  to: "calendar#list_card"
  post   "calendar/events",     to: "calendar#create_event"
  patch  "calendar/events/:id", to: "calendar#update_event",  as: :calendar_event
  delete "calendar/events/:id", to: "calendar#destroy_event"
  post "calendar/calls",      to: "calendar#create_call"
  get  "calendar/feed",       to: "calendar#feed", defaults: { format: "ics" }

  # ── #536: Kundenportal — eigene Mini-App unter /portal (live zusätzlich
  # über die Subdomain portal.miolim.de; der interne Rest ist auf dem
  # Portal-Host per ApplicationController-Guard gesperrt). ─────────────────
  namespace :portal do
    get    "login",          to: "sessions#new",     as: :login
    post   "login",          to: "sessions#create"
    # #619 Stufe 3: Sprache umschalten (DE/EN), auch ohne Login.
    get    "sprache/:locale", to: "sessions#set_locale", as: :set_locale,
           constraints: { locale: /de|en/ }
    get    "session/:token", to: "sessions#consume", as: :consume_session,
           constraints: { token: /[^\/]+/ }
    delete "session",        to: "sessions#destroy", as: :session

    root "pages#home"
    get  "roadmap",     to: "pages#roadmap"
    get  "termine",     to: "pages#termine"
    get  "dokumente",   to: "pages#dokumente"
    get  "dokumente/:id", to: "pages#artifact", as: :artifact
    get  "nachrichten", to: "pages#nachrichten"
    post "nachrichten", to: "pages#create_message"
  end
end
