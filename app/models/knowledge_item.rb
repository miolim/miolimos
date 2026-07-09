class KnowledgeItem < ApplicationRecord
  self.primary_key = :uuid

  # #602 S1: sichtbar = eigene KIs + KIs an sichtbaren Topics.
  include VisibleVia
  visible_via join: "KnowledgeItemTopic", join_fk: :knowledge_item_uuid,
              primary_key: :uuid

  has_many :knowledge_item_topics, foreign_key: :knowledge_item_uuid,
    primary_key: :uuid, dependent: :destroy
  has_many :topics, through: :knowledge_item_topics

  # Mentions: dieses KI nennt andere Person/Org-KIs ("@-Erwähnungen").
  # Ersetzt das frühere Contact-Modell — Personen/Orgs sind jetzt KIs.
  has_many :knowledge_item_mentions, foreign_key: :knowledge_item_uuid,
    primary_key: :uuid, dependent: :destroy
  has_many :mentioned_kis, through: :knowledge_item_mentions, source: :mentioned

  # #384 Phase 2 (Hans, 2026-05-27): @-Mentions auf App-Nutzer (Actor).
  # Adressierungs-Signal fuer den Dialog-Tab — extrahiert aus dem KI-Body.
  has_many :actor_mentions, foreign_key: :knowledge_item_uuid,
    primary_key: :uuid, dependent: :destroy
  has_many :mentioned_actors, through: :actor_mentions, source: :actor

  # Reverse: KIs, die dieses KI als Person/Org erwähnen.
  has_many :inbound_mentions, class_name: "KnowledgeItemMention",
    foreign_key: :mentioned_uuid, primary_key: :uuid, dependent: :destroy
  has_many :mentioning_kis, through: :inbound_mentions, source: :knowledge_item

  # Tasks/Communications, die dieses Person/Org-KI erwähnen.
  has_many :task_mentions, foreign_key: :mentioned_uuid, primary_key: :uuid, dependent: :destroy
  has_many :mentioning_tasks, through: :task_mentions, source: :task

  has_many :communication_mentions, foreign_key: :mentioned_uuid, primary_key: :uuid, dependent: :destroy
  has_many :mentioning_communications, through: :communication_mentions, source: :communication

  # Awaitings, die auf dieses Person-KI warten.
  has_many :awaitings, foreign_key: :contact_uuid, primary_key: :uuid, dependent: :nullify

  has_many :outgoing_references, class_name: "KnowledgeItemReference",
    foreign_key: :source_uuid, primary_key: :uuid, dependent: :destroy
  has_many :incoming_references, class_name: "KnowledgeItemReference",
    foreign_key: :target_uuid, primary_key: :uuid, dependent: :nullify

  # #239: typed Wikilink-Beziehungen (Relation-Model). Outgoing = ich
  # bin Source, incoming = ich bin Target. Beide Seiten sind polymorph;
  # source_type/target_type ist "KnowledgeItem".
  has_many :outgoing_relations, ->{ where(source_type: "KnowledgeItem") },
    class_name: "Relation", foreign_key: :source_uuid, primary_key: :uuid,
    dependent: :destroy
  has_many :incoming_relations, ->{ where(target_type: "KnowledgeItem") },
    class_name: "Relation", foreign_key: :target_uuid, primary_key: :uuid,
    dependent: :nullify

  # Affiliations: für Person-KIs die Verbindungen zu Organisationen
  # (Mitarbeiter, Autor, Mitglied …) mit Rolle + Zeitfenster.
  has_many :affiliations_as_person, class_name: "Affiliation",
    foreign_key: :person_uuid, primary_key: :uuid, dependent: :destroy
  has_many :affiliations_as_organization, class_name: "Affiliation",
    foreign_key: :organization_uuid, primary_key: :uuid, dependent: :destroy

  # Relationships: Person-Person (familienähnlich, professionell …).
  # Verzeichnete Beziehungen sind direktional (`from` → `to`); für
  # symmetrische Beziehungen schreibt man beide Richtungen oder nutzt
  # eine Convention im `kind`.
  has_many :outgoing_relationships, class_name: "Relationship",
    foreign_key: :from_uuid, primary_key: :uuid, dependent: :destroy
  has_many :incoming_relationships, class_name: "Relationship",
    foreign_key: :to_uuid, primary_key: :uuid, dependent: :destroy

  # Sub-Org-Hierarchie: ein Org-KI kann ein parent-Org-KI haben.
  # Beispiel: "BigCorp Engineering" mit `parent_org_uuid` auf "BigCorp".
  belongs_to :parent_org, class_name: "KnowledgeItem",
    foreign_key: :parent_org_uuid, primary_key: :uuid, optional: true
  has_many :sub_organizations, class_name: "KnowledgeItem",
    foreign_key: :parent_org_uuid, primary_key: :uuid

  # Kontaktdaten für Person/Org-KIs: N E-Mails/Telefone/Adressen,
  # jeweils mit Label. Schema.org-`contactPoint`-inspiriert.
  has_many :contact_points,
    foreign_key: :knowledge_item_uuid, primary_key: :uuid,
    dependent: :destroy

  # #544: ID-Nummern (Kundennummer/Steuernummer/…) dieses Person/Org-KI,
  # optional mit Gegenseite. Plus die Nummern, bei denen dieses KI die
  # vergebende Gegenseite ist (für die beidseitige Anzeige).
  has_many :identifiers,
    foreign_key: :knowledge_item_uuid, primary_key: :uuid,
    dependent: :destroy

  # #532: strukturierte Postadressen (EN16931-tauglich), DB-direkt.
  has_many :postal_addresses, -> { ordered },
    foreign_key: :knowledge_item_uuid, primary_key: :uuid,
    dependent: :destroy
  # #786: Bankverbindungen (mehrere möglich) am Person-/Org-KI.
  has_many :bank_accounts, -> { ordered },
    foreign_key: :knowledge_item_uuid, primary_key: :uuid,
    dependent: :destroy

  # Primäradresse fürs Dokument: bevorzugt billing, sonst erste.
  def primary_address
    postal_addresses.detect(&:billing) || postal_addresses.first
  end

  # #622: Versandanschrift fürs DIN-Fenster — bevorzugt die als
  # Postadresse markierte (Postfach etc.), sonst die primäre.
  def mailing_address
    postal_addresses.detect(&:post?) || primary_address
  end

  # #664: Zeichen, die die Wikilink-Ziel-Syntax brechen (s. WIKILINK_RE).
  WIKILINK_UNSAFE_TITLE = /[\[\]|#^]/

  # #664 (Hans, 2026-06-13): Wikilink mit Block-Anker, der AUCH bei
  # Titeln mit `|` `#` etc. trägt. YouTube-Titel enthalten oft ein `|`
  # (z. B. „… | Jaron Lanier") — `[[Titel^anker]]` zerlegte der Parser
  # dann am `|` (Alias-Trenner), der Anker landete im Alias und der Link
  # brach (klick → neues KI). Sichere Titel als `[[Titel^anker]]`;
  # unsichere als `[[uuid^anker|Titel]]` (UUID-Target trägt immer).
  def anchor_wikilink(anchor, alias_text: nil)
    display = alias_text.to_s.strip.presence
    if title.to_s.match?(WIKILINK_UNSAFE_TITLE)
      "[[#{uuid}^#{anchor}|#{display || title}]]"
    elsif display
      "[[#{title}^#{anchor}|#{display}]]"
    else
      "[[#{title}^#{anchor}]]"
    end
  end
  has_many :identifiers_as_counterparty, class_name: "Identifier",
    foreign_key: :counterparty_uuid, primary_key: :uuid,
    dependent: :nullify

  # Provenance: aus welchem InboxItem wurde dieses KI erzeugt? Optional.
  belongs_to :inbox_item, optional: true

  # Wer hat das KI angelegt. Optional, weil Bestände vor der creator-
  # Migration durch Backfill aus Git-Log nachgezogen werden und nicht
  # immer zuordenbar sind.
  belongs_to :creator, class_name: "Actor", optional: true

  # Bibliographische Quelle, die dieses KI zitiert (eine Notiz handelt
  # VON einer Quelle). locator_label/value strukturieren die Stelle
  # ("Rn. 14", "S. 33", "§ 3 Abs. 2").
  belongs_to :bib_source, class_name: "Source", optional: true

  # Wenn dieses KI eine Person/Org ist, kann es als Creator/Author auf
  # Quellen verweisen — das ist die Rückseite der SourceCreator-Tabelle.
  has_many :authored_source_links, class_name: "SourceCreator",
    foreign_key: :knowledge_item_uuid, primary_key: :uuid, dependent: :destroy
  has_many :authored_sources, through: :authored_source_links, source: :source

  # Klassifikation nach Beziehung zur Source statt nach Medium:
  #   - whole-source mit Volltext   → :transcript
  #   - whole-source paraphrasiert  → :abstract
  #   - excerpt wörtlich            → :direct_quote
  #   - excerpt paraphrasiert       → :indirect_quote
  #   - intern, frei                → :note
  #   - intern, an KI verankert     → :comment
  #
  # `:transcript` trägt sowohl die ehemaligen `web_clip`-MDs (Web-Volltext,
  # Whisper-Transkripte) als auch die ehemaligen `document`-Attachments
  # (PDF/Binary; file_path zeigt dann auf die Datei statt auf eine MD).
  # Bestand-MDs mit alten type-Strings (web_clip, ai_chat, quote, document)
  # werden vom Indexer transparent gemappt; ein einmaliges Backfill-Skript
  # schreibt das Frontmatter beim ersten Lauf um.
  enum :item_type, {
    note:           0,
    abstract:       1,  # ehemals ai_chat
    transcript:     2,  # ehemals web_clip; trägt jetzt auch PDF-Attachments
    direct_quote:   3,  # ehemals quote
    # Wert 4 (ehemals document) wandert auf transcript (2) per Migration.
    comment:        5,
    person:         6,
    organization:   7,
    doc:            8,  # Doku/Bedienungsanleitung — eigener Sidebar-Tab.
                        # `:doc` statt `:manual`, weil `source`-Enum auf
                        # KI bereits einen Wert `manual` hat (Provenance).
    indirect_quote: 9,
    synthesis:     10,  # #155 Phase 5b: Synthese-Notiz fuer ein Recherche-
                        # Topic. Agent schreibt initial, Mensch korrigiert
                        # punktuell. Display: research_question des
                        # zugeordneten Topics als Header.
    reply:         11,  # #384 Phase 3a (Hans, 2026-05-27): Dialog-
                        # Beitrag. parent_type+parent_id_int/parent_uuid
                        # zeigen auf den Eltern-Datensatz (KI oder Task).
                        # Titel optional — UI zeigt @author · zeit.
    image:         12   # #609 v3 (Hans): Bild-KIs als eigener Typ — filterbar.
  }

  # #705 (Hans, 2026-06-15): Body als Markdown (default) oder als HTML
  # rendern (sandboxed iframe). render_html?/render_markdown?,
  # render_html!/render_markdown!.
  enum :render_mode, { markdown: "markdown", html: "html" }, prefix: :render

  # #384 Phase 3a (Hans, 2026-05-27): Polymorphes Parent fuer
  # Reply-KIs. Tasks haben numerische id, KIs haben uuid — wir halten
  # beide getrennt, damit die FK-Indizes ordentlich greifen.
  scope :replies,           -> { where(item_type: :reply) }
  # #436 (Hans, 2026-06-01): Reply-KIs sind transaktionale Dialog-Beitraege
  # und sollen NICHT in den normalen Wissens-Browse-Listen auftauchen (sie
  # erben die Topics ihrer Parent-Task und tauchten dadurch z.B. im Topic-
  # Wissens-Tab auf). KEIN default_scope — Reply-Rendering/Editing/replies_for
  # und der Diskussions-Tab brauchen sie weiterhin; daher explizit an den
  # Browse-Queries.
  scope :non_reply,         -> { where.not(item_type: :reply) }
  # #932 (Hans): Browse-Listen „Wissen" zeigen echte Wissens-Items. Personen
  # und Organisationen haben eigene Reiter/Sektionen (Personen-Tab) und gehören
  # NICHT in die Wissens-Liste; Reply-KIs ebenso raus. Gleiches Ausschluss-
  # muster wie in der Volltextsuche (search_controller, persons/orgs = eigene
  # Kontakt-Sektion).
  scope :browsable,         -> { where.not(item_type: [:person, :organization, :reply]) }
  scope :published_replies, -> { replies.where.not(published_at: nil) }
  scope :draft_replies,     -> { replies.where(published_at: nil) }

  # Returnt das Eltern-Objekt (Task / KnowledgeItem / …) oder nil.
  def parent
    case parent_type
    when "Task"          then Task.find_by(id: parent_id_int)
    when "KnowledgeItem" then KnowledgeItem.find_by(uuid: parent_uuid)
    end
  end

  # #232/#564: Live-Updates fuer Antworten — Callbacks + Methoden liegen
  # gesammelt in KnowledgeItem::ReplyBroadcasts.
  include ReplyBroadcasts

  # #428 Phase 2 (Hans, 2026-05-31): tags-Array <-> zentrale Tag-Registry +
  # taggings synchron halten (KI-Tags kommen aus dem Frontmatter via Indexer,
  # landen aber in der tags-Spalte — der Hook greift also auch dort).
  after_save    :sync_taggings, if: :saved_change_to_tags?
  after_destroy :remove_taggings

  def sync_taggings  = TagSync.sync_ki(self)
  def remove_taggings
    Tagging.where(taggable_type: "KnowledgeItem", taggable_uuid: uuid).delete_all
  end

  # Reply-KIs bekommen eine User-facing Anzeige aus Autor + Zeit;
  # title bleibt nullable. Wenn doch ein Title gesetzt ist, gewinnt der.
  def display_label
    return title if title.present?
    return nil unless reply?
    author = creator&.name || "Unbekannt"
    time   = (published_at || created_at)&.strftime("%d.%m. %H:%M") || ""
    "#{author} · #{time}"
  end

  # Reply-KI ist editierbar solange der eigene Author dran ist UND noch
  # keine fremde Reply spaeter im selben Parent gepostet hat.
  # Hans-Spec (2026-05-27): „editierbar bis Antwort\".
  # #536 (Hans, 2026-06-10): Löschen ist von der „editierbar bis Antwort"-
  # Regel ENTKOPPELT — eigene Beiträge sind IMMER löschbar (Datenhygiene,
  # z.B. versehentlich gepostetes Secret). Bearbeiten bleibt eingefangen,
  # weil ein nachträglicher Edit den Kontext späterer Antworten verfälschen
  # kann; eine Löschung ist dagegen sichtbar und ehrlich.
  def deletable_by?(actor)
    return false unless actor
    return true  unless reply?
    creator_id == actor.id
  end

  def editable_by?(actor)
    return false unless actor
    return true  unless reply?
    return false if creator_id != actor.id
    # #522 (Hans, 2026-06-06): Eigene Entwürfe sind IMMER bearbeit-, lösch- und
    # veröffentlichbar — sie sind nicht Teil des Diskurses (nur der Autor sieht
    # sie), also darf eine spätere fremde Antwort sie nicht „einfangen". Ohne
    # diese Zeile blockierte die „editierbar bis Antwort"-Regel unten den
    # Entwurf, sobald jemand danach gepostet hatte (= der gemeldete Bug).
    return true  if published_at.nil?
    return true  if parent_type.blank?
    fk_col, fk_val = parent_type == "Task" ? [:parent_id_int, parent_id_int] : [:parent_uuid, parent_uuid]
    return true if fk_val.blank?
    KnowledgeItem.replies
                 .where(parent_type: parent_type, fk_col => fk_val)
                 .where("created_at > ?", created_at)
                 .where.not(creator_id: actor.id)
                 .none?
  end

  # Reply-Liste eines Eltern-Datensatzes (Task / KnowledgeItem),
  # chronologisch aufsteigend. Drafts NUR fuer den Autor selbst.
  def self.replies_for(parent, viewer: nil)
    parent_type = parent.is_a?(Task) ? "Task" : "KnowledgeItem"
    fk_col      = parent.is_a?(Task) ? :parent_id_int : :parent_uuid
    fk_val      = parent.is_a?(Task) ? parent.id      : parent.uuid
    scope = replies.where(parent_type: parent_type, fk_col => fk_val)
    if viewer
      scope = scope.where("published_at IS NOT NULL OR creator_id = ?", viewer.id)
    else
      scope = scope.where.not(published_at: nil)
    end
    # #522 (Hans, 2026-06-06): Eigene Entwürfe ans Ende des Threads — erst die
    # veröffentlichten Antworten, danach die Drafts. So ist ein Entwurf nie
    # zwischen späteren fremden Antworten „vergraben".
    # #522-Nachklapp: Veröffentlichte Antworten nach published_at sortieren,
    # NICHT nach created_at. Ein früh erstellter, spät veröffentlichter Entwurf
    # tritt erst beim Veröffentlichen in den Diskurs ein und gehört dann an
    # seine Veröffentlichungs-Position (Thread-Ende), nicht zurück an die alte
    # Entwurfsstelle. Drafts (published_at NULL) bleiben via COALESCE nach
    # created_at sortiert und durch das NULL-Kriterium ganz hinten.
    #
    # `.to_a`: Der Order ist roher Arel-SQL und damit NICHT umkehrbar. Alle
    # Aufrufer konsumieren das Ergebnis als Liste und rufen u.a. `.last(2)`
    # auf — auf einer Relation würde das `reverse_order` triggern und einen
    # ActiveRecord::IrreversibleOrderError werfen (500 beim Rendern jeder
    # Antworten-Sektion). Als Array ist `.last(2)` reines Ruby. (#523-Nachklapp)
    scope.order(Arel.sql("(published_at IS NULL), COALESCE(published_at, created_at)")).to_a
  end

  validates :uuid, presence: true, uniqueness: true
  # #384 Phase 3a: Reply-KIs sind titel-los, Identifikation ueber
  # Autor + Zeitstempel (siehe display_label). Andere item_types
  # behalten den Title-Pflicht-Check.
  validates :title, presence: true, unless: :reply?
  validates :file_path, presence: true, uniqueness: true
  validates :content_hash, presence: true

  # Soft-Delete: discard! statt destroy! — Default-Scope blendet
  # gelöschte aus, with_discarded/discarded gibt sie wieder her.
  # FileProxy.destroy/restore kümmern sich um die Markdown-Datei.
  default_scope { where(deleted_at: nil) }
  scope :with_discarded, -> { unscope(where: :deleted_at) }
  scope :discarded,      -> { with_discarded.where.not(deleted_at: nil) }

  def discard!
    update!(deleted_at: Time.current)
  end

  def undiscard!
    update!(deleted_at: nil)
  end

  def discarded?
    deleted_at.present?
  end

  # ─── Supersession (#460, Hans 2026-06-04) ────────────────────────────
  # Achse B der Versionierung: ein neues KI löst ein altes ab. Erstklassig
  # (Spalte, kein Relation-Modell), aber bewusst NICHT im default_scope —
  # „frühere Versionen bleiben erhalten und auffindbar". Listen/Suche
  # blenden Abgelöste per `not_superseded` aus, mit Toggle.
  belongs_to :superseded_by_actor, class_name: "Actor", optional: true

  scope :not_superseded, -> { where(superseded_by_uuid: nil) }
  scope :only_superseded, -> { where.not(superseded_by_uuid: nil) }

  def superseded?
    superseded_by_uuid.present?
  end

  # Das ablösende (neue) KI.
  def superseded_by
    return nil if superseded_by_uuid.blank?
    KnowledgeItem.find_by(uuid: superseded_by_uuid)
  end

  # KIs, die DIESES KI ablösen-… nein: die von diesem KI abgelöst werden,
  # d.h. deren Nachfolger ich bin (Backlink „Löst ab").
  def supersedes
    KnowledgeItem.where(superseded_by_uuid: uuid)
  end

  # Markiert dieses (alte) KI als abgelöst durch `successor`. Setzt die
  # Provenienz-Felder mit. Selbst-Ablösung und Zyklen werden verhindert.
  def mark_superseded_by!(successor, actor: nil)
    raise ArgumentError, "Ein KI kann sich nicht selbst ablösen" if successor.uuid == uuid
    if successor.superseded_by_uuid == uuid
      raise ArgumentError, "Zyklus: das Ziel wird bereits von diesem KI abgelöst"
    end
    update!(superseded_by_uuid: successor.uuid,
            superseded_at: Time.current,
            superseded_by_actor: actor)
  end

  def clear_supersession!
    update!(superseded_by_uuid: nil, superseded_at: nil, superseded_by_actor: nil)
  end

  scope :notes,           -> { where(item_type: :note) }
  scope :comments,        -> { where(item_type: :comment) }
  scope :abstracts,       -> { where(item_type: :abstract) }
  scope :transcripts,     -> { where(item_type: :transcript) }
  scope :direct_quotes,   -> { where(item_type: :direct_quote) }
  scope :indirect_quotes, -> { where(item_type: :indirect_quote) }
  scope :quotes,          -> { where(item_type: [:direct_quote, :indirect_quote]) }
  scope :persons,         -> { where(item_type: :person) }
  scope :organizations,   -> { where(item_type: :organization) }
  scope :syntheses,       -> { where(item_type: :synthesis) }
  scope :persons_and_orgs, -> { where(item_type: [:person, :organization]) }
  # #532: eigene Rechtssubjekte, aus denen Rechnungen ausgestellt werden.
  scope :issuers,          -> { where(issuer: true) }

  # Title-Lookup case-insensitive — sehr häufig (Wikilink-Auflösung,
  # Resolver, Importer). Vorher 6x als inline `where("lower(title) = ?", …)`.
  scope :by_title_ci, ->(title) { where("lower(title) = ?", title.to_s.strip.downcase) }

  # #840: Gibt es Kommunikation mit dieser Person? Steuert den blauen
  # Zustand des Haupt-Icons. Einzel-Query (indexierter EXISTS); in Listen
  # den gebatchten Set bauen und `known_via_comm:` explizit übergeben,
  # statt diese Methode pro Zeile aufzurufen (N+1).
  def known_via_communication?
    CommunicationMention.where(mentioned_uuid: uuid).exists?
  end

  # Anzeigename: Person → "Vorname Nachname", sonst Titel.
  def display_name
    if person?
      [first_name, last_name].compact_blank.join(" ").presence || title
    else
      title
    end
  end
end
