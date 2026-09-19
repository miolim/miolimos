require "test_helper"

class KnowledgeIndexerTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def write_md(base, relative_path, frontmatter:, body: "")
    full = base.join(relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, "---\n#{frontmatter.to_yaml.sub(/^---\n/, '')}---\n\n#{body}")
    full
  end

  test "indexes a fresh markdown file and returns stats" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      write_md(base, "knowledge/notes/test.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual", "topics" => [], "contacts" => [] },
        body:        "# Test Title\n\nBody"
      )

      stats = KnowledgeIndexer.run
      assert_equal 1, stats.scanned
      assert_equal 1, stats.created
      assert_equal 0, stats.updated

      item = KnowledgeItem.find(uuid)
      assert_equal "Test Title", item.title
      assert item.note?
    end
  end

  test "skips files without id in frontmatter" do
    with_isolated_miolimos_base do |base|
      write_md(base, "knowledge/notes/no-id.md",
        frontmatter: { "type" => "note" }, body: "# x"
      )

      stats = KnowledgeIndexer.run
      assert_equal 1, stats.scanned
      assert_equal 0, stats.created
      assert_equal 0, KnowledgeItem.count
    end
  end

  test "second run leaves unchanged items unchanged" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      write_md(base, "knowledge/notes/t.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual" },
        body:        "# T\n\nhello"
      )

      KnowledgeIndexer.run
      stats = KnowledgeIndexer.run
      assert_equal 1, stats.unchanged
      assert_equal 0, stats.updated
    end
  end

  test "detects changed content and updates the index" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      path = "knowledge/notes/t.md"
      write_md(base, path,
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual" },
        body:        "# T\n\nhello"
      )
      KnowledgeIndexer.run
      original_hash = KnowledgeItem.find(uuid).content_hash

      write_md(base, path,
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual" },
        body:        "# T\n\nUPDATED"
      )
      stats = KnowledgeIndexer.run

      assert_equal 1, stats.updated
      refute_equal original_hash, KnowledgeItem.find(uuid).content_hash
    end
  end

  test "orphaned index entries are removed when file is deleted" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      path = base.join("knowledge/notes/t.md")
      write_md(base, "knowledge/notes/t.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual" }, body: "# T"
      )
      KnowledgeIndexer.run
      assert KnowledgeItem.exists?(uuid)

      File.delete(path)
      stats = KnowledgeIndexer.run
      assert_equal 1, stats.orphaned
      refute KnowledgeItem.exists?(uuid)
    end
  end

  # #1675: Die aus Aufgaben-Kommentaren migrierten Antworten haben einen
  # file_path, aber nie eine Datei bekommen. Der Waisen-Lauf hielt sie für
  # „Datei gelöscht" und hätte sie hart vernichtet — ausgelöst durch jeden
  # erfolgreichen Wissens-Import in den Einstellungen.
  test "Antworten ohne Exportdatei ueberleben den Waisen-Lauf" do
    with_isolated_miolimos_base do |base|
      FileUtils.mkdir_p(base.join("knowledge"))
      eltern = FileProxy.create(actor: @hans, title: "Eltern-Notiz", item_type: :note, content: "x")
      antwort = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: nil, item_type: :reply,
                                      parent_uuid: eltern.uuid, creator_id: @hans.id,
                                      body: "Ein alter Aufgaben-Kommentar",
                                      file_path: "knowledge/replies/migrated-tc-1.md",
                                      content_hash: SecureRandom.hex(8))

      stats = KnowledgeIndexer.run

      assert KnowledgeItem.exists?(antwort.uuid), "die Antwort wurde als Waise gelöscht"
      assert_equal 0, stats.orphaned
      assert_equal "Ein alter Aufgaben-Kommentar", antwort.reload.body
    end
  end

  # #1675: Seit #241 ist die Datenbank die Quelle und die Datei ihr Export. Der
  # Indexer-Lauf schrieb trotzdem bei JEDER Datei Titel, Text, Namen, Arbeitgeber,
  # Tags und Aliasse aus der Datei zurück — auch wenn sie sich seit dem letzten
  # Export gar nicht geändert hatte. Alles, was inzwischen nur in der Datenbank
  # geändert wurde (Namens-Erkennung, Kontakt-Anreicherung, Titel von
  # Antworten), war danach wieder weg.
  test "eine unveraenderte Datei ueberschreibt nichts in der Datenbank" do
    with_isolated_miolimos_base do
      org    = FileProxy.create(actor: @hans, title: "Faro GmbH", item_type: :organization, content: "")
      person = FileProxy.create(actor: @hans, title: "Petra Probe", item_type: :person, content: "Stand A")
      KnowledgeIndexer.run   # Ausgangslage: Datei und Datenbank im Gleichschritt

      # Änderungen NUR in der Datenbank — so, wie Resolver/Anreicherung sie machen.
      person.update_columns(first_name: "Petra", last_name: "Probe", parent_org_uuid: org.uuid,
                            tags: ["kunde"], aliases: ["P. Probe"])

      stats = KnowledgeIndexer.run

      person.reload
      assert_equal ["Petra", "Probe"], [person.first_name, person.last_name], "die Namen wurden aus der alten Datei überschrieben"
      assert_equal org.uuid, person.parent_org_uuid, "der Arbeitgeber wurde abgeräumt"
      assert_equal [["kunde"], ["P. Probe"]], [person.tags, person.aliases]
      assert_operator stats.unchanged, :>=, 2
    end
  end

  # Die Gegenseite bleibt: Eine tatsächlich GEÄNDERTE Datei gewinnt — das ist
  # der Import-Fall (Datei von Hand oder von außen bearbeitet).
  test "eine geaenderte Datei gewinnt weiterhin" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      write_md(base, "knowledge/people/p.md",
        frontmatter: { "id" => uuid, "type" => "person", "first_name" => "Alt" }, body: "# Petra Probe\n\nA")
      KnowledgeIndexer.run
      KnowledgeItem.find(uuid).update_columns(first_name: "NurDatenbank")

      write_md(base, "knowledge/people/p.md",
        frontmatter: { "id" => uuid, "type" => "person", "first_name" => "Neu" }, body: "# Petra Probe\n\nB")
      KnowledgeIndexer.run

      assert_equal "Neu", KnowledgeItem.find(uuid).first_name
    end
  end

  test "creates missing topics from frontmatter slugs" do
    with_isolated_miolimos_base do |base|
      refute Topic.exists?(slug: "brand-new-topic")

      write_md(base, "knowledge/notes/t.md",
        frontmatter: { "id" => SecureRandom.uuid, "type" => "note", "source" => "manual",
                       "topics" => ["brand-new-topic"] },
        body:        "# T"
      )
      KnowledgeIndexer.run

      topic = Topic.find_by(slug: "brand-new-topic")
      assert_not_nil topic
      assert_equal "Brand New Topic", topic.name
    end
  end

  test "creates missing person-KIs from frontmatter slugs" do
    with_isolated_miolimos_base do |base|
      refute KnowledgeItem.persons.where("title ILIKE ?", "Jane Doe").exists?
      write_md(base, "knowledge/notes/t.md",
        frontmatter: { "id" => SecureRandom.uuid, "type" => "note", "source" => "manual",
                       "contacts" => ["jane-doe"] },
        body:        "# T"
      )
      KnowledgeIndexer.run

      jane = KnowledgeItem.persons.find_by(title: "Jane Doe")
      assert_not_nil jane
      assert_equal "Jane", jane.first_name
      assert_equal "Doe",  jane.last_name
    end
  end

  test "wikilink parsing: plain [[Title]] resolves to existing item" do
    with_isolated_miolimos_base do |base|
      uuid_a = SecureRandom.uuid
      uuid_b = SecureRandom.uuid

      write_md(base, "knowledge/notes/target.md",
        frontmatter: { "id" => uuid_b, "type" => "note", "source" => "manual" },
        body:        "# Target\n\nTarget body"
      )
      write_md(base, "knowledge/notes/source.md",
        frontmatter: { "id" => uuid_a, "type" => "note", "source" => "manual" },
        body:        "# Source\n\nSee [[Target]]."
      )

      KnowledgeIndexer.run
      ref = KnowledgeItem.find(uuid_a).outgoing_references.first
      assert_equal "Target", ref.target_title
      assert_equal uuid_b, ref.target_uuid
      assert ref.file?
      assert_nil ref.anchor_text
    end
  end

  test "wikilink parsing: heading anchor [[Title#Heading]]" do
    with_isolated_miolimos_base do |base|
      write_md(base, "knowledge/notes/s.md",
        frontmatter: { "id" => SecureRandom.uuid, "type" => "note", "source" => "manual" },
        body:        "# S\n\n[[Other#Cost Analysis]]"
      )

      KnowledgeIndexer.run
      ref = KnowledgeItemReference.first
      assert_equal "Other", ref.target_title
      assert ref.heading?
      assert_equal "Cost Analysis", ref.anchor_text
      assert_nil ref.target_uuid
    end
  end

  test "wikilink parsing: block anchor [[Title^block-id]]" do
    with_isolated_miolimos_base do |base|
      write_md(base, "knowledge/notes/s.md",
        frontmatter: { "id" => SecureRandom.uuid, "type" => "note", "source" => "manual" },
        body:        "# S\n\n[[Other^abc123]]"
      )

      KnowledgeIndexer.run
      ref = KnowledgeItemReference.first
      assert_equal "Other", ref.target_title
      assert ref.block?
      assert_equal "abc123", ref.anchor_text
    end
  end

  test "wikilink parsing: alias [[Title|Display]] keeps title" do
    with_isolated_miolimos_base do |base|
      write_md(base, "knowledge/notes/s.md",
        frontmatter: { "id" => SecureRandom.uuid, "type" => "note", "source" => "manual" },
        body:        "# S\n\nSiehe [[Ringprojekt|Patent Ring]]."
      )

      KnowledgeIndexer.run
      ref = KnowledgeItemReference.first
      assert_equal "Ringprojekt", ref.target_title
      assert ref.file?
    end
  end

  test "wikilinks to not-yet-existing targets leave target_uuid nil and resolve later" do
    with_isolated_miolimos_base do |base|
      uuid_src = SecureRandom.uuid
      write_md(base, "knowledge/notes/src.md",
        frontmatter: { "id" => uuid_src, "type" => "note", "source" => "manual" },
        body:        "# Src\n\nSee [[FutureTarget]]."
      )
      KnowledgeIndexer.run
      assert_nil KnowledgeItem.find(uuid_src).outgoing_references.first.target_uuid

      uuid_tgt = SecureRandom.uuid
      write_md(base, "knowledge/notes/tgt.md",
        frontmatter: { "id" => uuid_tgt, "type" => "note", "source" => "manual" },
        body:        "# FutureTarget\n\nbody"
      )
      KnowledgeIndexer.run

      refreshed = KnowledgeItem.find(uuid_src).outgoing_references.first
      assert_equal uuid_tgt, refreshed.target_uuid
    end
  end

  test "multiple wikilinks in one file all get recorded" do
    with_isolated_miolimos_base do |base|
      write_md(base, "knowledge/notes/s.md",
        frontmatter: { "id" => SecureRandom.uuid, "type" => "note", "source" => "manual" },
        body:        "# S\n\n[[A]] and [[B]] and [[C#heading]]"
      )

      KnowledgeIndexer.run
      assert_equal 3, KnowledgeItemReference.count
      assert_equal %w[A B C].sort, KnowledgeItemReference.pluck(:target_title).sort
    end
  end

  # #953: Aufgaben-Referenzen [[#id]] landen mit target_task_id im Index.
  test "aufgaben-referenz [[#id]] wird mit target_task_id indexiert" do
    with_isolated_miolimos_base do |base|
      task = Task.create!(title: "Ziel-Aufgabe", creator: @hans)
      uuid = SecureRandom.uuid
      write_md(base, "knowledge/notes/s.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual" },
        body:        "# S\n\nSiehe [[##{task.id}]] und [[#999999|kaputt]]."
      )

      KnowledgeIndexer.run
      refs = KnowledgeItem.find(uuid).outgoing_references
      assert_equal 1, refs.count, "nicht existierende Task-IDs werden nicht erfasst"
      ref = refs.first
      assert_equal task.id, ref.target_task_id
      assert_equal "##{task.id}", ref.target_title
      assert_nil ref.target_uuid
      assert_includes task.incoming_references, ref
    end
  end

  # ── #953 Folge: Task-BESCHREIBUNGEN als Referenz-Quellen ────────────────
  test "task-beschreibung indexiert [[#id]]- und [[Titel]]-Links, ohne Selbstverweis" do
    with_isolated_miolimos_base do
      ziel = Task.create!(title: "Ziel-Aufgabe-B", creator: @hans)
      ki   = FileProxy.create(actor: @hans, title: "Ziel-Notiz-B", item_type: :note, content: "x")
      quelle = Task.create!(title: "Quell-Aufgabe-B", creator: @hans)
      quelle.update!(description: "Siehe [[##{ziel.id}]], [[Ziel-Notiz-B]] und mich selbst [[##{quelle.id}]].")

      refs = quelle.outgoing_references.reload
      assert_equal 2, refs.count, "Selbstverweis wird nicht erfasst"
      task_ref = refs.find { |r| r.target_task_id.present? }
      ki_ref   = refs.find { |r| r.target_uuid.present? }
      assert_equal ziel.id, task_ref.target_task_id
      assert_equal ki.uuid, ki_ref.target_uuid, "KI-Titel wird sofort aufgelöst"

      assert_includes ziel.backlink_sources, quelle
      assert_includes ki.incoming_references.map(&:source_object), quelle

      # Beschreibung ändern ersetzt die Refs; Task-Löschung räumt sie ab.
      quelle.update!(description: "nur noch [[##{ziel.id}]]")
      assert_equal 1, quelle.outgoing_references.reload.count
      quelle.destroy!
      assert_equal 0, KnowledgeItemReference.where(source_task_id: quelle.id).count
    end
  end

  test "KI-Umbenennung rewritet Titel-Wikilinks auch in Task-Beschreibungen" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Alter Titel C", item_type: :note, content: "x")
      quelle = Task.create!(title: "Quell-Aufgabe-C", creator: @hans,
                            description: "Sieh [[Alter Titel C]] an.")
      FileProxy.update(actor: @hans, knowledge_item: target, title: "Neuer Titel C")
      quelle.reload
      assert_includes quelle.description, "[[Neuer Titel C]]"
      ref = quelle.outgoing_references.sole
      assert_equal target.uuid, ref.target_uuid
      assert_equal "Neuer Titel C", ref.target_title
    end
  end

  test "re-indexing replaces old references for the same source" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      path = "knowledge/notes/s.md"
      write_md(base, path,
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual" },
        body:        "# S\n\n[[Old]]"
      )
      KnowledgeIndexer.run
      assert_equal ["Old"], KnowledgeItem.find(uuid).outgoing_references.pluck(:target_title)

      write_md(base, path,
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual" },
        body:        "# S\n\n[[New]]"
      )
      KnowledgeIndexer.run
      assert_equal ["New"], KnowledgeItem.find(uuid).outgoing_references.pluck(:target_title)
    end
  end

  test "unchanged file: references are NOT rebuilt (row IDs stable)" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      write_md(base, "knowledge/notes/s.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual" },
        body:        "# S\n\n[[Somewhere]]"
      )
      KnowledgeIndexer.run
      ref_ids_before = KnowledgeItem.find(uuid).outgoing_references.pluck(:id).sort

      stats = KnowledgeIndexer.run
      assert_equal 1, stats.unchanged

      ref_ids_after = KnowledgeItem.find(uuid).outgoing_references.pluck(:id).sort
      assert_equal ref_ids_before, ref_ids_after,
        "unchanged-path must not destroy/recreate reference rows"
    end
  end

  test "renaming a target re-resolves references: resolved → nil" do
    with_isolated_miolimos_base do |base|
      src_uuid = SecureRandom.uuid
      tgt_uuid = SecureRandom.uuid

      write_md(base, "knowledge/notes/target.md",
        frontmatter: { "id" => tgt_uuid, "type" => "note", "source" => "manual" },
        body:        "# Original Title"
      )
      write_md(base, "knowledge/notes/source.md",
        frontmatter: { "id" => src_uuid, "type" => "note", "source" => "manual" },
        body:        "# Src\n\n[[Original Title]]"
      )
      KnowledgeIndexer.run
      ref = KnowledgeItem.find(src_uuid).outgoing_references.first
      assert_equal tgt_uuid, ref.target_uuid

      # Rename target (content changes — frontmatter UUID stays)
      write_md(base, "knowledge/notes/target.md",
        frontmatter: { "id" => tgt_uuid, "type" => "note", "source" => "manual" },
        body:        "# Completely New Name"
      )
      KnowledgeIndexer.run

      assert_nil KnowledgeItem.find(src_uuid).outgoing_references.first.target_uuid,
        "reference must un-resolve when target title no longer matches"
    end
  end

  # ─── Sidecar / binary documents ──────────────────────────────────────────

  def write_binary_with_sidecar(base, rel_path, content_bytes:, frontmatter:)
    full = base.join(rel_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, content_bytes)

    sidecar = Pathname.new("#{full}.meta.yml")
    sidecar.write(frontmatter.to_yaml)
    [full, sidecar]
  end

  test "sidecar: PDF with .meta.yml is indexed as transcript with correct hash" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      payload = "%PDF-1.4 fake"
      write_binary_with_sidecar(
        base, "knowledge/documents/report.pdf",
        content_bytes: payload,
        frontmatter: {
          "id" => uuid, "type" => "document", "source" => "import",
          "title" => "Annual Report"
        }
      )

      stats = KnowledgeIndexer.run

      # Scanner sieht sowohl die .meta.yml als auch nichts für die nackte Datei,
      # darum scanned=1 (sidecar) plus ggf. einen Pass für das Markdown-Glob.
      assert stats.scanned >= 1
      assert_equal 1, stats.created

      item = KnowledgeItem.find(uuid)
      # `document` im Frontmatter wird vom Indexer auf transcript gemappt
      # (Bestand-Alias); transcript trägt jetzt auch Binär-Attachments.
      assert item.transcript?
      assert_equal "Annual Report", item.title
      assert_equal "knowledge/documents/report.pdf", item.file_path
      assert_equal Digest::SHA256.hexdigest(payload), item.content_hash
    end
  end

  test "sidecar without binary beside it is ignored" do
    with_isolated_miolimos_base do |base|
      FileUtils.mkdir_p(base.join("knowledge/documents"))
      orphan_sidecar = base.join("knowledge/documents/missing.pdf.meta.yml")
      orphan_sidecar.write({ "id" => SecureRandom.uuid, "type" => "document" }.to_yaml)

      stats = KnowledgeIndexer.run
      assert_equal 0, stats.created, "sidecar without its binary must be skipped"
    end
  end

  test "sidecar is re-hashed when the binary changes (update path)" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      binary_path, _ = write_binary_with_sidecar(
        base, "knowledge/documents/file.pdf",
        content_bytes: "v1",
        frontmatter: { "id" => uuid, "type" => "document", "title" => "F" }
      )
      KnowledgeIndexer.run
      first_hash = KnowledgeItem.find(uuid).content_hash

      File.binwrite(binary_path, "v2")
      stats = KnowledgeIndexer.run

      assert_equal 1, stats.updated
      refute_equal first_hash, KnowledgeItem.find(uuid).content_hash
    end
  end

  test "sidecar also links topics from frontmatter" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      write_binary_with_sidecar(
        base, "knowledge/documents/report.pdf",
        content_bytes: "pdf-bytes",
        frontmatter: {
          "id" => uuid, "type" => "document", "title" => "Report",
          "topics" => ["patent-ring"]
        }
      )
      KnowledgeIndexer.run
      assert_equal ["patent-ring"], KnowledgeItem.find(uuid).topics.pluck(:slug)
    end
  end

  test "markdown without frontmatter heading falls back to filename-derived title" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      full = base.join("knowledge/notes/2026-04-19-mein-titel.md")
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, "---\nid: #{uuid}\ntype: note\nsource: manual\n---\n\nplain body without heading")

      KnowledgeIndexer.run
      assert_equal "Mein Titel", KnowledgeItem.find(uuid).title
    end
  end

  test "resolution moves to a new item when a different file takes the old title" do
    with_isolated_miolimos_base do |base|
      src_uuid  = SecureRandom.uuid
      first_uuid  = SecureRandom.uuid
      second_uuid = SecureRandom.uuid

      write_md(base, "knowledge/notes/first.md",
        frontmatter: { "id" => first_uuid, "type" => "note", "source" => "manual" },
        body:        "# Shared Title"
      )
      write_md(base, "knowledge/notes/src.md",
        frontmatter: { "id" => src_uuid, "type" => "note", "source" => "manual" },
        body:        "# Src\n\n[[Shared Title]]"
      )
      KnowledgeIndexer.run
      assert_equal first_uuid, KnowledgeItem.find(src_uuid).outgoing_references.first.target_uuid

      # The first file is renamed away and a second file now owns the old title
      write_md(base, "knowledge/notes/first.md",
        frontmatter: { "id" => first_uuid, "type" => "note", "source" => "manual" },
        body:        "# Renamed Away"
      )
      write_md(base, "knowledge/notes/second.md",
        frontmatter: { "id" => second_uuid, "type" => "note", "source" => "manual" },
        body:        "# Shared Title"
      )
      KnowledgeIndexer.run

      assert_equal second_uuid, KnowledgeItem.find(src_uuid).outgoing_references.first.target_uuid,
        "resolver should follow the current owner of the title"
    end
  end

  test "creator-Frontmatter wird beim Indizieren auf creator_id aufgelöst" do
    with_isolated_miolimos_base do |base|
      hans   = create_human(name: "Hans-Indexed")
      uuid   = SecureRandom.uuid
      write_md(base, "knowledge/notes/c.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual",
                       "creator" => "Hans-Indexed" },
        body: "# C\n\nHi"
      )
      KnowledgeIndexer.run
      assert_equal hans.id, KnowledgeItem.find(uuid).creator_id
    end
  end

  test "creator-Frontmatter ohne match lässt creator_id NULL" do
    with_isolated_miolimos_base do |base|
      uuid = SecureRandom.uuid
      write_md(base, "knowledge/notes/d.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual",
                       "creator" => "Es Gibt Mich Nicht" },
        body: "# D"
      )
      KnowledgeIndexer.run
      assert_nil KnowledgeItem.find(uuid).creator_id
    end
  end

  test "creator_id wird beim Re-Index nicht überschrieben, wenn schon gesetzt" do
    with_isolated_miolimos_base do |base|
      original = create_human(name: "Original-Creator")
      uuid     = SecureRandom.uuid
      write_md(base, "knowledge/notes/e.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual",
                       "creator" => "Original-Creator" },
        body: "# E"
      )
      KnowledgeIndexer.run
      assert_equal original.id, KnowledgeItem.find(uuid).creator_id

      # Frontmatter-Creator-Name ändern; DB-creator_id bleibt vorhanden,
      # also darf der Indexer nicht erneut auflösen und überschreiben.
      other = create_human(name: "Anderer")
      write_md(base, "knowledge/notes/e.md",
        frontmatter: { "id" => uuid, "type" => "note", "source" => "manual",
                       "creator" => "Anderer" },
        body: "# E geändert"
      )
      KnowledgeIndexer.run
      assert_equal original.id, KnowledgeItem.find(uuid).creator_id,
        "Indexer fasst creator_id nur an, wenn DB ihn noch nicht hat"
    end
  end

  # ─── Class-Level Entry Points (#203 Phase E.9) ───────────────────────
  # Diese drei Methoden werden von FileProxy::Writer direkt gerufen —
  # nicht ueber KnowledgeIndexer.run. Eigene Tests sichern den
  # bevorstehenden References-Modul-Refactor ab.

  test "resolve_parent_org_uuid akzeptiert UUID-Form und liefert sie lowercased" do
    uuid = SecureRandom.uuid.upcase
    assert_equal uuid.downcase, KnowledgeIndexer.resolve_parent_org_uuid(uuid)
  end

  test "resolve_parent_org_uuid loest Title case-insensitiv auf existierendes KI" do
    org = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "ACME GmbH",
                                 item_type: "organization", creator: @hans,
                                 file_path: "knowledge/organizations/acme.md",
                                 content_hash: "h")
    assert_equal org.uuid, KnowledgeIndexer.resolve_parent_org_uuid("acme gmbh")
    assert_nil KnowledgeIndexer.resolve_parent_org_uuid("nicht-da")
    assert_nil KnowledgeIndexer.resolve_parent_org_uuid("")
  end

  test "index_body_references_for legt OutgoingReferences fuer Wikilinks an" do
    src = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Quelle",
                                 item_type: "note", creator: @hans,
                                 file_path: "knowledge/notes/q.md", content_hash: "h")
    target = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Ziel",
                                    item_type: "note", creator: @hans,
                                    file_path: "knowledge/notes/z.md", content_hash: "h2")
    body = "Ein Verweis auf [[Ziel]] und einen [[Nicht-Existiert]]."
    KnowledgeIndexer.index_body_references_for(src, body)
    refs = src.reload.outgoing_references.order(:id).to_a
    assert_equal 2, refs.size
    assert_equal target.uuid, refs.first.target_uuid
    assert_nil refs.last.target_uuid, "Unaufloesbares Target bleibt vorlaeufig nil"
    assert_equal "Nicht-Existiert", refs.last.target_title
  end

  test "resolve_dangling_references_to ersetzt nil-target_uuid retroaktiv per Title-Match" do
    src = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Q",
                                 item_type: "note", creator: @hans,
                                 file_path: "knowledge/notes/q.md", content_hash: "h")
    later = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Spaeter-Erstellt",
                                   item_type: "note", creator: @hans,
                                   file_path: "knowledge/notes/sp.md", content_hash: "h2")
    KnowledgeItemReference.create!(source_uuid: src.uuid,
                                    target_title: "Spaeter-Erstellt", target_uuid: nil,
                                    anchor_type: "file")
    KnowledgeIndexer.resolve_dangling_references_to("Spaeter-Erstellt", later.uuid)
    ref = src.reload.outgoing_references.first
    assert_equal later.uuid, ref.target_uuid
  end

  # #475 (Hans, 2026-06-02): Anker-only `[[^id]]`-Links erzeugen eine
  # Referenz (Ziel via KnowledgeItemAnchor) — Voraussetzung dafuer, dass
  # Backlinks auf Antwort-Absaetze ueberhaupt erfasst werden.
  test "anchor-only Link [[^id]] erzeugt eine Block-Referenz auf das Anker-KI" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Ziel", item_type: :note,
                                content: "Wichtiger Absatz. ^a1b2c3d4\n")
      KnowledgeItemAnchor.find_or_create_by!(anchor: "a1b2c3d4",
                                             knowledge_item_uuid: target.uuid)
      source = FileProxy.create(actor: @hans, title: "Quelle-475", item_type: :note,
                                content: "Siehe [[^a1b2c3d4]].")
      ref = source.outgoing_references.find_by(anchor_text: "a1b2c3d4")
      assert ref, "Anker-only-Referenz wurde nicht erzeugt"
      assert_equal "block", ref.anchor_type
      assert_equal target.uuid, ref.target_uuid
    end
  end
end
