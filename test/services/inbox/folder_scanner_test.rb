require "test_helper"

class Inbox::FolderScannerTest < ActiveSupport::TestCase
  def with_inbox(&block)
    Dir.mktmpdir("inbox-scanner-") do |tmp|
      inbox = Pathname.new(tmp)
      yield inbox
    end
  end

  def make_scanner(actor, inbox)
    Inbox::FolderScanner.new(actor: actor, inbox: inbox)
  end

  test "creates inbox_items for each .md file and moves the source to .processed/" do
    actor = create_human
    with_inbox do |inbox|
      a = inbox.join("note-a.md")
      b = inbox.join("note-b.md")
      a.write("# A\nbody A")
      b.write("# B\nbody B")

      created = nil
      assert_difference -> { InboxItem.count }, 2 do
        created = make_scanner(actor, inbox).run
      end
      assert_equal 2, created.size

      # Source files relocated.
      refute a.exist?, "expected source file to be moved out of inbox"
      refute b.exist?
      processed_dir = inbox.join(".processed", Date.current.iso8601)
      assert processed_dir.exist?
      moved = processed_dir.children.map { |p| p.basename.to_s }.sort
      assert_equal %w[note-a.md note-b.md], moved

      created.each do |item|
        assert_equal "markdown", item.source_kind
        assert_equal "pending", item.status
        assert item.raw_content.start_with?("# ")
        assert_match %r{/\.processed/}, item.external_path
      end
    end
  end

  test "ensures inbox dir, .processed subdir, and .gitignore exist" do
    actor = create_human
    Dir.mktmpdir("inbox-init-") do |tmp|
      missing = Pathname.new(tmp).join("does-not-exist-yet")
      refute missing.exist?
      make_scanner(actor, missing).run

      assert missing.exist?
      assert missing.join(".processed").exist?
      gi = missing.join(".gitignore")
      assert gi.exist?
      assert_includes gi.read, "*"
    end
  end

  test "ignores non-markdown files" do
    actor = create_human
    with_inbox do |inbox|
      inbox.join("readme.txt").write("not markdown")
      inbox.join("note.md").write("# Yes")

      assert_difference -> { InboxItem.count }, 1 do
        make_scanner(actor, inbox).run
      end
      assert (inbox.join("readme.txt")).exist?, "non-md file must stay in place"
    end
  end

  test "skips a file that fails to ingest and continues with the rest" do
    actor = create_human
    with_inbox do |inbox|
      good = inbox.join("good.md"); good.write("# good")
      # Force validation failure on the second file by filling raw_content
      # with an unsupported source_kind via a stub on `create!`.
      bad  = inbox.join("bad.md");  bad.write("# bad")

      original = InboxItem.method(:create!)
      InboxItem.singleton_class.send(:define_method, :create!) do |attrs|
        raise ActiveRecord::RecordInvalid.new(InboxItem.new) if attrs[:title] == "bad"
        original.call(attrs)
      end
      begin
        assert_difference -> { InboxItem.count }, 1 do
          make_scanner(actor, inbox).run
        end
      ensure
        InboxItem.singleton_class.send(:remove_method, :create!)
      end
      refute good.exist?, "successful file moved out"
      assert bad.exist?,  "failed file stays in place for retry"
    end
  end
end
