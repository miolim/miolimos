require "test_helper"

class FileProxy::PathsTest < ActiveSupport::TestCase
  test "type_to_subdir maps canonical item types" do
    assert_equal "notes",         FileProxy::Paths.type_to_subdir("note")
    assert_equal "abstracts",     FileProxy::Paths.type_to_subdir("abstract")
    assert_equal "transcripts",   FileProxy::Paths.type_to_subdir("transcript")
    assert_equal "quotes",        FileProxy::Paths.type_to_subdir("direct_quote")
    assert_equal "quotes",        FileProxy::Paths.type_to_subdir(:quote)
    assert_equal "notes",         FileProxy::Paths.type_to_subdir("comment")
    assert_equal "people",        FileProxy::Paths.type_to_subdir("person")
    assert_equal "organizations", FileProxy::Paths.type_to_subdir("organization")
    assert_equal "docs",          FileProxy::Paths.type_to_subdir("doc")
  end

  test "type_to_subdir maps legacy aliases to current subdirs" do
    assert_equal "abstracts",   FileProxy::Paths.type_to_subdir("ai_chat")
    assert_equal "transcripts", FileProxy::Paths.type_to_subdir("web_clip")
    assert_equal "transcripts", FileProxy::Paths.type_to_subdir("document")
  end

  test "type_to_subdir falls back to notes for unknown types" do
    assert_equal "notes", FileProxy::Paths.type_to_subdir("anything_unknown")
    assert_equal "notes", FileProxy::Paths.type_to_subdir(nil)
  end

  test "unique_relative_path returns a fresh slug-derived path under knowledge/" do
    with_isolated_miolimos_base do
      p = FileProxy::Paths.unique_relative_path(subdir: "notes", slug: "demo")
      assert_match %r{\Aknowledge/notes/\d{4}-\d{2}-\d{2}-demo\.md\z}, p
    end
  end

  test "unique_relative_path appends a random suffix on disk collision" do
    with_isolated_miolimos_base do |base|
      first = FileProxy::Paths.unique_relative_path(subdir: "notes", slug: "demo")
      full = base.join(first)
      FileUtils.mkdir_p(full.dirname)
      File.write(full, "x")

      second = FileProxy::Paths.unique_relative_path(subdir: "notes", slug: "demo")
      refute_equal first, second
      assert_match %r{\Aknowledge/notes/\d{4}-\d{2}-\d{2}-demo-[a-z0-9]{4}\.md\z}, second
    end
  end

  test "unique_relative_path appends a random suffix on DB collision" do
    with_isolated_miolimos_base do
      hans = create_human
      grant(hans, "KnowledgeItem", %w[create])
      ki = FileProxy.create(actor: hans, title: "Demo", item_type: :note, content: "")
      taken_path = ki.file_path
      assert_match %r{\Aknowledge/notes/\d{4}-\d{2}-\d{2}-demo\.md\z}, taken_path

      second = FileProxy::Paths.unique_relative_path(subdir: "notes", slug: "demo")
      refute_equal taken_path, second
    end
  end

  test "unique_relative_path honours the extension keyword for binary uploads" do
    with_isolated_miolimos_base do
      p = FileProxy::Paths.unique_relative_path(subdir: "docs", slug: "report", extension: ".pdf")
      assert_match %r{\.pdf\z}, p
    end
  end
end
