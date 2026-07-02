require "test_helper"

class WikiImporterTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    @inbox = Pathname.new(Dir.mktmpdir("miolim-inbox-test"))
    Current.actor = @hans
  end

  teardown do
    FileUtils.rm_rf(@inbox.to_s) if @inbox && @inbox.exist?
  end

  def write(filename, content)
    path = @inbox.join(filename)
    File.write(path, content)
    path
  end

  test "voll-Frontmatter: legt neue ai_chat-KI an, Datei wird gelöscht" do
    write("foo.md", <<~MD)
      ---
      title: Test-Chat
      source: claude
      source_url: https://claude.ai/chat/abc
      topics: [miolimos]
      ---

      # Test-Chat

      ## Session 2026-04-27

      Hello world.
    MD

    results = WikiImporter.new(actor: @hans, inbox: @inbox).run
    assert_equal 1, results.size
    assert_equal :created, results.first.outcome

    item = results.first.item
    assert_equal "Test-Chat", item.title
    assert_equal "abstract", item.item_type
    assert_equal "https://claude.ai/chat/abc", item.bib_source&.url
    refute @inbox.join("foo.md").exist?
  end

  test "Light-Header: 'Titel: …' und 'Datum: …' werden erkannt" do
    write("light.md", <<~MD)
      Titel: Webrecherche
      Datum: 27.04.2026
      Quelle: https://chatgpt.com/c/xyz

      Erste Erkenntnisse zur API.
    MD

    results = WikiImporter.new(actor: @hans, inbox: @inbox).run
    assert_equal :created, results.first.outcome
    item = results.first.item
    assert_equal "Webrecherche", item.title
    assert_equal "https://chatgpt.com/c/xyz", item.bib_source&.url
  end

  test "ohne erkennbares Frontmatter: Filename wird zum Title" do
    write("meine-recherche.md", "Inhalt ohne Header.\n")
    results = WikiImporter.new(actor: @hans, inbox: @inbox).run
    assert_equal :created, results.first.outcome
    assert_equal "Meine Recherche", results.first.item.title
  end

  test "Title-Match: zweites File mit gleichem Title hängt an erstes an" do
    write("first.md", <<~MD)
      Titel: Brainstorm zu Knowledge-Workflow
      Datum: 2026-04-27

      Erste Ideen.
    MD
    WikiImporter.new(actor: @hans, inbox: @inbox).run

    write("second.md", <<~MD)
      Titel: Brainstorm zu Knowledge-Workflow
      Datum: 2026-04-28

      Zweite Ideen.
    MD

    results = WikiImporter.new(actor: @hans, inbox: @inbox).run
    assert_equal :appended, results.first.outcome

    item = KnowledgeItem.where("lower(title) = ?", "brainstorm zu knowledge-workflow").first
    body = FileProxy.read(actor: @hans, knowledge_item: item)
    assert_includes body, "## Session 2026-04-27"
    assert_includes body, "## Session 2026-04-28"
    assert_includes body, "Erste Ideen"
    assert_includes body, "Zweite Ideen"
  end

  test "source_url-Match hat Vorrang vor Title-Match" do
    write("a.md", <<~MD)
      ---
      title: Originaltitel
      source_url: https://claude.ai/chat/zzz
      ---

      ## Session 2026-04-27

      A
    MD
    WikiImporter.new(actor: @hans, inbox: @inbox).run

    # Zweites File: anderer Title, gleiche source_url → muss matchen
    write("b.md", <<~MD)
      ---
      title: Anderer Titel
      source_url: https://claude.ai/chat/zzz
      ---

      ## Session 2026-04-28

      B
    MD

    results = WikiImporter.new(actor: @hans, inbox: @inbox).run
    assert_equal :appended, results.first.outcome

    item = KnowledgeItem.joins(:bib_source).where(sources: { url: "https://claude.ai/chat/zzz" }).first
    body = FileProxy.read(actor: @hans, knowledge_item: item)
    assert_includes body, "A"
    assert_includes body, "B"
  end

  test "append_to-UUID hat Vorrang vor allem" do
    write("a.md", <<~MD)
      ---
      title: Quell-Notiz
      ---

      Erst.
    MD
    initial = WikiImporter.new(actor: @hans, inbox: @inbox).run.first.item

    write("b.md", <<~MD)
      ---
      title: Komplett anderer Titel
      append_to: #{initial.uuid}
      ---

      Zweit.
    MD

    results = WikiImporter.new(actor: @hans, inbox: @inbox).run
    assert_equal :appended, results.first.outcome
    # #241 Plan B: nach Append-Side-Effekt das AR-Objekt frisch laden,
    # damit Reader die neue Body-Spalte sieht.
    initial.reload
    body = FileProxy.read(actor: @hans, knowledge_item: initial)
    assert_includes body, "Erst"
    assert_includes body, "Zweit"
  end

  test "Append merged Topics/Tags als Union" do
    write("a.md", <<~MD)
      ---
      title: Tag-Test
      tags: [chat, api]
      ---

      Erste.
    MD
    WikiImporter.new(actor: @hans, inbox: @inbox).run

    write("b.md", <<~MD)
      ---
      title: Tag-Test
      tags: [chat, oauth]
      ---

      Zweite.
    MD
    WikiImporter.new(actor: @hans, inbox: @inbox).run

    item = KnowledgeItem.where("lower(title) = ?", "tag-test").first
    body = FileProxy.read(actor: @hans, knowledge_item: item)
    # Frontmatter im Body sollte alle drei Tags haben
    assert_match(/tags:[\s\S]*chat/, body)
    assert_match(/tags:[\s\S]*api/, body)
    assert_match(/tags:[\s\S]*oauth/, body)
  end
end
