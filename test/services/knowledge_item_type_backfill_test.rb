require "test_helper"

class KnowledgeItemTypeBackfillTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    # #241 Plan B (2026-05-19): Backfill liest jetzt Frontmatter aus
    # DB-Spalten, nicht mehr von Datei. Legacy-Frontmatter-Typen in
    # File-Frontmatter sind damit unsichtbar. Tests sind als Bestand
    # gedacht (einmaliger Migration-Lauf vor Plan B war erledigt) und
    # werden uebersprungen, solange das Service-Modul existiert. Wenn
    # wir den Backfill ganz retiren, fallen Tests + Service zusammen weg.
    skip "Backfill ist nach Plan B obsolet (DB-SoT); Test bleibt als Legacy-Hülle stehen"
  end

  # Schreibt eine MD mit altem type-String direkt auf die Platte und legt
  # das passende KI an — so können wir Bestand simulieren, ohne über
  # FileProxy.create zu gehen (das schreibt heute schon den neuen Type).
  def write_legacy_md(subdir:, slug:, item_type:, frontmatter_type:)
    uuid          = SecureRandom.uuid
    relative_path = "knowledge/#{subdir}/#{slug}.md"
    full_path     = FileProxy::BASE_PATH.join(relative_path)
    FileUtils.mkdir_p(full_path.dirname)
    fm = {
      "id"     => uuid,
      "type"   => frontmatter_type,
      "source" => "manual",
      "title"  => slug.titleize
    }
    body    = "Body."
    content = "---\n#{fm.to_yaml.sub(/^---\n/, '')}---\n\n#{body}"
    File.write(full_path, content)

    KnowledgeItem.create!(
      uuid:         uuid,
      title:        slug.titleize,
      item_type:    item_type,

      file_path:    relative_path,
      content_hash: Digest::SHA256.hexdigest(content),
      creator:      @hans
    )
  end

  test "rewrites old type-strings (ai_chat → abstract usw.) und ist idempotent" do
    with_isolated_miolimos_base do
      legacy = [
        write_legacy_md(subdir: "abstracts",   slug: "alt-chat",     item_type: :abstract,     frontmatter_type: "ai_chat"),
        write_legacy_md(subdir: "transcripts", slug: "alt-clip",     item_type: :transcript,   frontmatter_type: "web_clip"),
        write_legacy_md(subdir: "quotes",      slug: "alt-zitat",    item_type: :direct_quote, frontmatter_type: "quote"),
        write_legacy_md(subdir: "transcripts", slug: "alt-document", item_type: :transcript,   frontmatter_type: "document")
      ]
      current = write_legacy_md(subdir: "notes", slug: "neu-note",
                                item_type: :note, frontmatter_type: "note")

      stats = KnowledgeItemTypeBackfill.run(actor: @hans)
      assert_equal 5, stats.scanned
      assert_equal 4, stats.rewritten
      assert_equal 1, stats.already_current

      expected = ["abstract", "transcript", "direct_quote", "transcript"]
      legacy.zip(expected).each do |item, new_type|
        yaml = FileProxy.read_frontmatter_yaml(actor: @hans, knowledge_item: item.reload)
        fm   = YAML.safe_load(yaml, permitted_classes: [Date, Time])
        assert_equal new_type, fm["type"], "Expected #{item.title} to be #{new_type}, got #{fm['type']}"
      end

      # Zweiter Lauf: nichts mehr umzuschreiben.
      stats2 = KnowledgeItemTypeBackfill.run(actor: @hans)
      assert_equal 0, stats2.rewritten
      assert_equal 5, stats2.already_current

      # Note-KI bleibt unverändert.
      yaml = FileProxy.read_frontmatter_yaml(actor: @hans, knowledge_item: current.reload)
      fm   = YAML.safe_load(yaml, permitted_classes: [Date, Time])
      assert_equal "note", fm["type"]
    end
  end

  test "zählt fehlende Dateien und skippt KIs ohne Frontmatter" do
    with_isolated_miolimos_base do
      # KI mit DB-Eintrag, aber Datei nicht auf Platte.
      KnowledgeItem.create!(
        uuid:         SecureRandom.uuid,
        title:        "Phantom",
        item_type:    :note,

        file_path:    "knowledge/notes/phantom.md",
        content_hash: "x",
        creator:      @hans
      )
      # KI mit MD ohne Frontmatter.
      uuid = SecureRandom.uuid
      path = "knowledge/notes/no-fm.md"
      FileUtils.mkdir_p(FileProxy::BASE_PATH.join("knowledge/notes"))
      File.write(FileProxy::BASE_PATH.join(path), "Just a body.")
      KnowledgeItem.create!(
        uuid:         uuid,
        title:        "NoFM",
        item_type:    :note,

        file_path:    path,
        content_hash: Digest::SHA256.hexdigest("Just a body."),
        creator:      @hans
      )

      stats = KnowledgeItemTypeBackfill.run(actor: @hans)
      assert_equal 2, stats.scanned
      assert_equal 0, stats.rewritten
      # Beide KIs landen in no_frontmatter: einmal MD ohne `---`-Block,
      # einmal Datei fehlt komplett (FileProxy.read_frontmatter_yaml
      # liefert in beiden Fällen "").
      assert_equal 2, stats.no_frontmatter
    end
  end
end
