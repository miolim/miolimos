# #1075: Zwei Person-/Organisations-KIs zu einem zusammenführen.
#
# Entsteht, wenn dieselbe reale Person mehrfach erfasst wurde (typisch:
# Auto-Anlage durch den Gmail-Sync, nachdem eine E-Mail-Adresse vom
# „richtigen" Eintrag entfernt wurde). Der Merge zieht alle Daten und
# Verweise der Quelle auf das Ziel um und legt die Quelle in den
# Papierkorb.
#
# Semantik:
#   - Ziel gewinnt: Stammdaten des Ziels bleiben; Quelle füllt nur
#     leere Felder auf.
#   - Kontaktpunkte/Adressen/Bankkonten/Identifier wandern, Duplikate
#     (gleicher Wert) werden verworfen.
#   - Alle UUID-Verweise (Mentions, Relations, Dokumente, Rechnungen,
#     Affiliations, …) zeigen danach aufs Ziel; Joins mit Unique-Index
#     deduplizieren, was durch den Merge doppelt würde.
#   - Der Quell-Titel (+ deren Aliases) wird Alias des Ziels — bestehende
#     `[[Titel]]`-Wikilinks in fremden Bodies lösen weiter auf, ohne dass
#     fremde Texte umgeschrieben werden. (UUID-Form-Wikilinks auf die
#     Quelle bleiben als bewusste Lücke stehen — kommen praktisch nicht
#     vor, und ein Rewrite fremder Bodies wäre invasiver als der Nutzen.)
#   - Quell-Body wird, falls vorhanden, unter einer Herkunfts-Überschrift
#     an den Ziel-Body angehängt.
#   - Quelle geht per FileProxy.destroy in den Papierkorb (Datei
#     restaurierbar; die umgehängten Verweise bleiben beim Ziel).
class EntityMerge
  class Error < StandardError; end

  MERGEABLE_TYPES = %w[person organization].freeze

  def self.merge!(source:, target:, actor:)
    new(source, target, actor).merge!
  end

  def initialize(source, target, actor)
    @source = source
    @target = target
    @actor  = actor
    @report = Hash.new(0)
  end

  # Führt den Merge aus und liefert einen Report-Hash
  # (Kategorie => Anzahl umgezogener Datensätze).
  def merge!
    validate!
    AccessGate.authorize!(actor: @actor, resource_type: "KnowledgeItem", action: "update")
    AccessGate.authorize!(actor: @actor, resource_type: "KnowledgeItem", action: "delete")

    KnowledgeItem.transaction do
      move_contact_points
      move_postal_addresses
      move_bank_accounts
      move_identifiers
      repoint_references
      fill_flags
    end

    # Datei-Operationen nach der DB-Transaktion: erst das Ziel kanonisch
    # neu schreiben (Aliases, Stammdaten-Lücken, Body-Append → Export +
    # Reindex + Git), dann die Quelle in den Papierkorb.
    export_target!
    FileProxy.destroy(actor: @actor, knowledge_item: @source)

    @report
  end

  private

  def validate!
    raise Error, "Quelle und Ziel müssen verschieden sein" if @source.uuid == @target.uuid
    unless MERGEABLE_TYPES.include?(@source.item_type) && MERGEABLE_TYPES.include?(@target.item_type)
      raise Error, "Nur Personen und Organisationen können zusammengeführt werden"
    end
    raise Error, "Quelle ist bereits gelöscht" if @source.discarded?
    raise Error, "Ziel ist gelöscht" if @target.discarded?
  end

  # ─── Strukturierte Kontaktdaten ────────────────────────────────────

  def move_contact_points
    existing = @target.contact_points.map { |c| [c.kind, c.value.to_s.strip.downcase] }.to_set
    @source.contact_points.to_a.each do |cp|
      key = [cp.kind, cp.value.to_s.strip.downcase]
      if existing.include?(key)
        cp.destroy
      else
        cp.update_columns(knowledge_item_uuid: @target.uuid)
        existing << key
        @report[:contact_points] += 1
      end
    end
  end

  def move_postal_addresses
    norm = ->(a) { [a.line1, a.line2, a.postal_code, a.city, a.country].map { |v| v.to_s.strip.downcase } }
    existing = @target.postal_addresses.map(&norm).to_set
    @source.postal_addresses.to_a.each do |pa|
      key = norm.call(pa)
      if existing.include?(key)
        pa.destroy
      else
        pa.update_columns(knowledge_item_uuid: @target.uuid)
        existing << key
        @report[:postal_addresses] += 1
      end
    end
  end

  def move_bank_accounts
    norm = ->(b) { b.iban.to_s.gsub(/\s+/, "").upcase }
    existing = @target.bank_accounts.map(&norm).to_set
    @source.bank_accounts.to_a.each do |ba|
      key = norm.call(ba)
      if existing.include?(key)
        ba.destroy
      else
        ba.update_columns(knowledge_item_uuid: @target.uuid)
        existing << key
        @report[:bank_accounts] += 1
      end
    end
  end

  def move_identifiers
    existing = Identifier.where(knowledge_item_uuid: @target.uuid)
                         .map { |i| [i.label.to_s.strip.downcase, i.value.to_s.strip.downcase] }.to_set
    Identifier.where(knowledge_item_uuid: @source.uuid).to_a.each do |ident|
      key = [ident.label.to_s.strip.downcase, ident.value.to_s.strip.downcase]
      if existing.include?(key)
        ident.destroy
      else
        ident.update_columns(knowledge_item_uuid: @target.uuid)
        existing << key
        @report[:identifiers] += 1
      end
    end
  end

  # ─── UUID-Verweise umhängen ────────────────────────────────────────

  # Alle Tabellen, die per UUID auf ein Person-/Org-KI zeigen. `unique_by`
  # nennt die Spalten, die zusammen mit der umgehängten Spalte einen
  # Unique-Index bilden — entstünde ein Duplikat, wird die Quell-Zeile
  # verworfen statt umgehängt. `drop_if` verwirft Zeilen, die durch den
  # Merge selbstbezüglich würden (z.B. Beziehung Quelle↔Ziel).
  def repoint_references
    repoint KnowledgeItemMention, :mentioned_uuid, unique_by: [:knowledge_item_uuid],
            drop_if: ->(r) { r.knowledge_item_uuid == @target.uuid }
    repoint KnowledgeItemMention, :knowledge_item_uuid, unique_by: [:mentioned_uuid],
            drop_if: ->(r) { r.mentioned_uuid == @target.uuid }
    repoint TaskMention, :mentioned_uuid, unique_by: [:task_id]
    repoint CommunicationMention, :mentioned_uuid, unique_by: [:communication_id, :role]
    repoint ActorMention, :knowledge_item_uuid, unique_by: [:actor_id]

    # Ausgehende Referenzen der Quelle löschen — falls ihr Body ans Ziel
    # angehängt wird, baut der Reindex des Ziels sie neu auf.
    KnowledgeItemReference.where(source_uuid: @source.uuid).delete_all
    repoint KnowledgeItemReference, :target_uuid,
            drop_if: ->(r) { r.source_uuid == @target.uuid }

    repoint Affiliation, :person_uuid, unique_by: [:organization_uuid, :role, :start_at],
            drop_if: ->(r) { r.organization_uuid == @target.uuid }
    repoint Affiliation, :organization_uuid, unique_by: [:person_uuid, :role, :start_at],
            drop_if: ->(r) { r.person_uuid == @target.uuid }
    repoint Relationship, :from_uuid, unique_by: [:to_uuid, :kind, :start_at],
            drop_if: ->(r) { r.to_uuid == @target.uuid }
    repoint Relationship, :to_uuid, unique_by: [:from_uuid, :kind, :start_at],
            drop_if: ->(r) { r.from_uuid == @target.uuid }
    repoint Relation, :source_uuid, unique_by: [:anchor_id],
            drop_if: ->(r) { r.target_uuid == @target.uuid }
    repoint Relation, :target_uuid,
            drop_if: ->(r) { r.source_uuid == @target.uuid }

    repoint Tagging, :taggable_uuid, unique_by: [:tag_id, :taggable_type]
    repoint KnowledgeItemTopic, :knowledge_item_uuid, unique_by: [:topic_id]
    repoint KnowledgeItemPin, :knowledge_item_id, unique_by: [:actor_id]
    repoint KnowledgeItemAnchor, :knowledge_item_uuid
    repoint SourceCreator, :knowledge_item_uuid, unique_by: [:source_id, :role]

    repoint Document, :issuer_uuid
    repoint Document, :recipient_uuid
    repoint Document, :body_ki_uuid
    repoint Invoice, :issuer_uuid
    repoint Invoice, :recipient_uuid
    repoint Identifier, :counterparty_uuid
    repoint Awaiting, :contact_uuid
    repoint Actor, :person_ki_uuid
    repoint TimeEntry, :subject_uuid
    repoint Topic, :customer_uuid
    repoint WorkNode, :knowledge_item_uuid

    # Kinder der Quelle: Replies/Kommentare (parent_uuid) und — bei Orgs —
    # zugeordnete Personen/Unter-Orgs (parent_org_uuid). with_discarded,
    # damit auch Papierkorb-Einträge nicht auf die tote Quelle zeigen.
    repoint KnowledgeItem.with_discarded, :parent_uuid
    repoint KnowledgeItem.with_discarded, :parent_org_uuid
    repoint KnowledgeItem.with_discarded, :superseded_by_uuid
  end

  def repoint(scope, column, unique_by: nil, drop_if: nil)
    model = scope.respond_to?(:klass) ? scope.klass : scope
    label = "#{model.table_name}.#{column}"
    pk    = model.primary_key
    scope.where(column => @source.uuid).order(pk).to_a.each do |row|
      if drop_if&.call(row)
        row.destroy
        next
      end
      if unique_by
        conflict = scope.where(column => @target.uuid)
                        .where(unique_by.index_with { |c| row[c] })
                        .where.not(pk => row[pk]).exists?
        if conflict
          row.destroy
          next
        end
      end
      row.update_columns(column => @target.uuid)
      @report[label.to_sym] += 1
    end
  end

  # ─── Stammdaten & Export ───────────────────────────────────────────

  # Boolean-Flags leben nicht im FileProxy.update-Parametersatz —
  # direkt setzen (OR-Semantik: einmal bekannt, bleibt bekannt).
  def fill_flags
    if @source.personally_known? && !@target.personally_known?
      @target.update!(personally_known: true)
      @report[:personally_known] += 1
    end
  end

  # Ein kanonischer Schreibvorgang aufs Ziel: Aliases, Stammdaten-Lücken
  # und Body-Append zusammen — FileProxy.update exportiert die Datei,
  # committet und reindiziert.
  def export_target!
    # Frisch laden: die Association-Caches (contact_points etc.) sind nach
    # den Moves stale — der Frontmatter-Export würde sonst die gerade
    # umgehängten Datensätze als „nicht deklariert" wieder wegräumen.
    @target.reload

    params = { actor: @actor, knowledge_item: @target }

    params[:aliases] = merged_aliases
    # Kontaktpunkte explizit deklarieren (identische Menge wie in der DB):
    # so trägt die exportierte Datei die zusammengeführten Kontakte, und
    # der ersetzende Sync ist ein No-op.
    params[:contact_points] = @target.contact_points.ordered.map do |c|
      { "kind" => c.kind, "label" => c.label.to_s, "value" => c.value }
    end

    %i[first_name last_name gender salutation academic_title orcid legal_form].each do |attr|
      next if @target[attr].present? || @source[attr].blank?
      params[attr] = @source[attr]
    end
    if @target.parent_org_uuid.blank? && @source.parent_org_uuid.present?
      params[:parent_org] = @source.parent_org_uuid
    end
    params[:issuer] = true if @source.issuer? && !@target.issuer?

    if @source.body.present?
      params[:content] = merged_body
      @report[:body_appended] += 1
    end

    FileProxy.update(**params)
  end

  def merged_aliases
    taken  = [@target.title.to_s.strip.downcase]
    merged = []
    (Array(@target.aliases) + [@source.title] + Array(@source.aliases)).each do |a|
      a = a.to_s.strip
      next if a.blank? || taken.include?(a.downcase)
      taken << a.downcase
      merged << a
    end
    merged
  end

  def merged_body
    addendum = "## Aus „#{@source.title}“ übernommen\n\n#{@source.body.strip}\n"
    return addendum if @target.body.blank?

    "#{@target.body.rstrip}\n\n#{addendum}"
  end
end
