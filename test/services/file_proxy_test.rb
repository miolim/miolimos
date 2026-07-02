require "test_helper"

class FileProxyTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])

    @classifier = create_agent
    grant(@classifier, "KnowledgeItem", %w[read])
    grant(@classifier, "KnowledgeItem", %w[delete], effect: :deny)
  end

  test "create raises Unauthorized for actor without create capability" do
    with_isolated_miolimos_base do
      assert_raises(AccessGate::Unauthorized) do
        FileProxy.create(
          actor: @classifier, title: "Nope", item_type: :note, content: "x"
        )
      end
    end
  end

  test "create writes markdown file with YAML frontmatter and persists KnowledgeItem" do
    with_isolated_miolimos_base do |base|
      item = FileProxy.create(
        actor:     @hans,
        title:     "My Note",
        item_type: :note,

        content:   "Body text.",
        topics:    ["patent-ring"],
        tags:      ["architektur"]
      )

      assert item.persisted?
      assert_equal "My Note", item.title
      assert_match(%r{\Aknowledge/notes/\d{4}-\d{2}-\d{2}-my-note\.md\z}, item.file_path)

      full_path = base.join(item.file_path)
      assert File.exist?(full_path)
      content = File.read(full_path)

      assert content.start_with?("---\n")
      # Psych-Emitter quotet UUIDs in manchen Versionen — beide Varianten OK
      assert_match(/id:\s*['"]?#{item.uuid}['"]?/, content)
      assert_includes content, "type: note"
      assert_includes content, "creator: Hans"
      refute_match(/^source:\s/, content, "source-Enum wurde gestrichen")
      assert_includes content, "# My Note"
      assert_includes content, "Body text."
      assert_equal @hans.id, item.creator_id
    end
  end

  test "read_frontmatter_yaml returns the YAML between --- markers for .md files" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "FM-Test",
                              item_type: :note, content: "Body.")
      yaml = FileProxy.read_frontmatter_yaml(actor: @hans, knowledge_item: item)
      assert_match(/^id:/, yaml)
      assert_match(/^type: note$/, yaml)
      assert_match(/^creator: Hans$/, yaml)
      refute_match(/^---/, yaml, "Marker selbst sollten nicht im Output sein")
      refute_match(/Body\./, yaml, "Body-Inhalt sollte nicht im Frontmatter-Output landen")
    end
  end

  test "merge_frontmatter! adds new fields and bumps updated_at without touching body" do
    with_isolated_miolimos_base do
      # #241 Plan B: bib_source-Slug resolved jetzt gegen die Sources-DB,
      # darum vorab eine Source mit dem Test-Slug anlegen.
      Source.create!(slug: "yt-abc", title: "YT Probe", csl_type: "motion_picture",
                     creator: @hans)
      item = FileProxy.create(actor: @hans, title: "Merge-Test",
                              item_type: :note,
                              content: "Original-Body.")
      FileProxy.merge_frontmatter!(actor: @hans, knowledge_item: item,
                                    bib_source: "yt-abc",
                                    provenance: { "origin" => "inbox" })
      yaml = FileProxy.read_frontmatter_yaml(actor: @hans, knowledge_item: item)
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_match(/^bib_source: yt-abc$/, yaml)
      assert_match(/origin: inbox/, yaml)
      assert_match(/Original-Body\./, body, "Body bleibt unangetastet")
    end
  end

  test "merge_frontmatter! preserves keys it does not touch" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "Keep-Keys",
                              item_type: :note,
                              content: "x", tags: ["alpha"])
      FileProxy.merge_frontmatter!(actor: @hans, knowledge_item: item,
                                    bib_source: "src-1")
      yaml = FileProxy.read_frontmatter_yaml(actor: @hans, knowledge_item: item)
      assert_match(/- alpha$/, yaml, "Bestehende tags bleiben unverändert")
      assert_match(/^creator: Hans$/, yaml, "creator wird nicht überschrieben")
    end
  end

  test "read_frontmatter_yaml rekonstruiert YAML aus DB-Spalten (Plan B #241)" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "Plan-B Probe",
                              item_type: :note, content: "body")
      yaml = FileProxy.read_frontmatter_yaml(actor: @hans, knowledge_item: item)
      assert_match(/^id: /, yaml)
      assert_match(/^type: note$/, yaml)
      assert_match(/^title: Plan-B Probe$/, yaml)
    end
  end

  test "create routes item_type to correct subdir" do
    with_isolated_miolimos_base do
      {
        note:           "knowledge/notes",
        abstract:       "knowledge/abstracts",
        transcript:     "knowledge/transcripts",
        direct_quote:   "knowledge/quotes",
        indirect_quote: "knowledge/quotes",
        comment:        "knowledge/notes",
        doc:            "knowledge/docs"
      }.each do |type, expected_dir|
        item = FileProxy.create(
          actor: @hans, title: "X-#{type}", item_type: type, content: "c"
        )
        assert item.file_path.start_with?(expected_dir), "#{type} should land in #{expected_dir}, got #{item.file_path}"
      end
    end
  end

  test "content_hash matches sha256 of file contents" do
    with_isolated_miolimos_base do |base|
      item = FileProxy.create(
        actor: @hans, title: "Hash Check", item_type: :note, content: "abc"
      )
      actual = Digest::SHA256.hexdigest(File.read(base.join(item.file_path)))
      assert_equal actual, item.content_hash
    end
  end

  test "create git-commits with actor as author and miolimOS as committer" do
    with_isolated_miolimos_base do |base|
      FileProxy.create(
        actor: @hans, title: "Committed", item_type: :note, content: "x"
      )

      log = Dir.chdir(base) do
        `git log -1 "--format=%an|%ae|%cn|%ce"`.strip
      end
      author_name, author_email, committer_name, committer_email = log.split("|")

      assert_equal @hans.name,  author_name
      assert_equal @hans.email, author_email
      assert_equal "miolimOS",              committer_name
      assert_equal "system@miolimos.local", committer_email
    end
  end

  test "agent without email gets miolimos.local fallback in commit" do
    with_isolated_miolimos_base do |base|
      grant(@classifier, "KnowledgeItem", %w[read create])

      FileProxy.create(
        actor: @classifier, title: "From Agent", item_type: :note, content: "x"
      )

      email = Dir.chdir(base) { `git log -1 "--format=%ae"`.strip }
      assert email.end_with?("@miolimos.local"), "fallback email, got: #{email}"
    end
  end

  test "read returns file contents for authorized actor" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @hans, title: "Readable", item_type: :note, content: "hidden gold"
      )
      content = FileProxy.read(actor: @hans, knowledge_item: item)
      assert_includes content, "hidden gold"
    end
  end

  test "read raises Unauthorized when actor lacks read" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @hans, title: "Secret", item_type: :note, content: "x"
      )

      grant(@classifier, "KnowledgeItem", %w[read], effect: :deny)
      assert_raises(AccessGate::Unauthorized) do
        FileProxy.read(actor: @classifier, knowledge_item: item)
      end
    end
  end

  test "read liefert auch dann was zurueck, wenn die Datei weg ist (Plan B #241 — DB-SoT)" do
    with_isolated_miolimos_base do |base|
      item = FileProxy.create(
        actor: @hans, title: "Gone", item_type: :note, content: "x"
      )

      File.delete(base.join(item.file_path))
      raw = FileProxy.read(actor: @hans, knowledge_item: item)
      assert_match(/^---\n/, raw, "Frontmatter aus DB rekonstruiert")
      assert_match(/^# Gone\b/, raw, "H1 mit Title aus DB")
    end
  end

  test "title-rewrite propagiert auch in src.body (Plan B #241)" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Alter Name", item_type: :note, content: "Zielinhalt.")
      source = FileProxy.create(actor: @hans, title: "Quelle", item_type: :note,
                                content: "Sieh mal [[Alter Name]] — wichtig.")
      # Reference muss existieren, sonst kein Rewrite-Trigger
      assert_equal 1, source.outgoing_references.count
      FileProxy.update(actor: @hans, knowledge_item: target, title: "Neuer Name")
      source.reload
      assert_includes source.body, "[[Neuer Name]]"
      refute_includes source.body, "[[Alter Name]]"
    end
  end

  test "topics: slugs are linked in DB immediately after create" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @hans, title: "Linked Note", item_type: :note,
        content: "x", topics: ["patent-ring", "new-auto-topic"]
      )

      slugs = item.topics.pluck(:slug).sort
      assert_equal %w[new-auto-topic patent-ring], slugs
    end
  end

  test "contacts: slugs are linked in DB immediately after create" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @hans, title: "With Contact", item_type: :note,
        content: "x", contacts: ["thomas-lederer", "anthropic"]
      )

      titles = item.mentioned_kis.pluck(:title).sort
      assert_equal ["Anthropic", "Thomas Lederer"], titles
      types = item.mentioned_kis.pluck(:item_type).sort
      assert_equal %w[organization person], types
    end
  end

  test "existing topic is reused (no duplicate created)" do
    with_isolated_miolimos_base do
      existing = create_topic(creator: @hans, slug: "already-there")
      item = FileProxy.create(
        actor: @hans, title: "Reuses", item_type: :note,
        content: "x", topics: ["already-there"]
      )
      assert_equal [existing], item.topics
    end
  end

  test "create with colliding title appends unique suffix to filename" do
    with_isolated_miolimos_base do
      a = FileProxy.create(actor: @hans, title: "Same Day Same Title",
                           item_type: :note, content: "1")
      b = FileProxy.create(actor: @hans, title: "Same Day Same Title",
                           item_type: :note, content: "2")
      refute_equal a.file_path, b.file_path
      assert_match(/-[a-z0-9]{4}\.md\z/, b.file_path)
      assert File.exist?(FileProxy::BASE_PATH.join(a.file_path))
      assert File.exist?(FileProxy::BASE_PATH.join(b.file_path))
    end
  end

  test "create with empty/non-slugifiable title still produces a valid path" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "...",
                              item_type: :note, content: "x")
      assert_match(/\A\d{4}-\d{2}-\d{2}-(note|\.\.\.)/, File.basename(item.file_path))
      assert File.exist?(FileProxy::BASE_PATH.join(item.file_path))
    end
  end

  # #477 (Hans, 2026-06-02): migrierte Reply-KIs (knowledge/replies/) haben
  # nie eine Datei bekommen, das Verzeichnis existiert nicht. Jede Schreib-
  # Operation (z.B. wrap_highlight beim Selektions-Anker) lief in ENOENT.
  # update muss das Verzeichnis just-in-time anlegen statt zu brechen.
  test "update legt fehlendes Verzeichnis + Datei neu an statt ENOENT" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "Migrated-477",
                              item_type: :note, content: "Erster Absatz.")
      full = FileProxy::BASE_PATH.join(item.file_path)
      FileUtils.rm_rf(File.dirname(full))
      refute File.exist?(full)
      assert_nothing_raised do
        FileProxy.update(actor: @hans, knowledge_item: item,
                         content: "Erster Absatz.\n\nNeuer Absatz mit Anker. ^a1b2c3d4")
      end
      assert File.exist?(full), "Datei wurde nicht just-in-time angelegt"
    end
  end

  # #532 (Hans, 2026-06-07): Stammdaten-Fundament — USt-IdNr + Aussteller-Flag
  # müssen durch FileProxy.update in DB-Spalten UND Frontmatter landen und über
  # Teil-Updates erhalten bleiben (Round-Trip via build_frontmatter_hash).
  # #761: vat_id-Spalte entfernt — USt-IdNr lebt als Identifier (#544). Hier
  # bleibt nur das issuer-Flag samt Persistenz über Teil-Updates.
  test "update schreibt issuer und erhält es über Teil-Updates" do
    with_isolated_miolimos_base do
      org = FileProxy.create(actor: @hans, title: "Meine Firma GmbH",
                             item_type: :organization, content: "")
      FileProxy.update(actor: @hans, knowledge_item: org, issuer: true)
      org.reload
      assert org.issuer?, "issuer-Flag wurde nicht gesetzt"

      yaml = FileProxy.read_frontmatter_yaml(actor: @hans, knowledge_item: org)
      assert_includes yaml, "issuer: true"

      # Teil-Update an einem anderen Feld darf issuer nicht verlieren.
      FileProxy.update(actor: @hans, knowledge_item: org, title: "Meine Firma GmbH 2")
      org.reload
      assert org.issuer?, "issuer ging bei Teil-Update verloren"

      # Aussteller-Flag wieder entfernen.
      FileProxy.update(actor: @hans, knowledge_item: org, issuer: false)
      org.reload
      refute org.issuer?, "issuer wurde nicht zurückgesetzt"
    end
  end
end
