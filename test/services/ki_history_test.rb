require "test_helper"

class KiHistoryTest < ActiveSupport::TestCase
  def write_and_commit(base, rel, body, msg)
    full = base.join(rel)
    full.dirname.mkpath
    File.write(full, body)
    Dir.chdir(base) do
      system("git", "add", rel.to_s)
      system("git", "-c", "user.name=test", "-c", "user.email=t@t",
             "commit", "-q", "-m", msg)
    end
  end

  test "log returns commits newest-first with parsed metadata" do
    with_isolated_miolimos_base do |base|
      write_and_commit(base, "knowledge/note.md", "v1", "init note")
      write_and_commit(base, "knowledge/note.md", "v2", "second pass")

      commits = KiHistory.for_path("knowledge/note.md")
      assert_equal 2, commits.size
      assert_equal "second pass", commits.first.subject
      assert_equal "init note",   commits.last.subject
      assert_equal 8, commits.first.short_sha.length
      assert commits.first.date.is_a?(Time)
      assert_equal "test", commits.first.author
    end
  end

  test "log limit caps the number of returned commits" do
    with_isolated_miolimos_base do |base|
      4.times { |i| write_and_commit(base, "knowledge/n.md", "v#{i}", "rev #{i}") }
      assert_equal 2, KiHistory.for_path("knowledge/n.md", limit: 2).size
    end
  end

  test "log returns empty array on empty rel_path" do
    with_isolated_miolimos_base do
      assert_equal [], KiHistory.for_path("")
    end
  end

  test "show returns the file contents at the given revision" do
    with_isolated_miolimos_base do |base|
      write_and_commit(base, "knowledge/n.md", "v1\n", "init")
      sha = `git -C #{base} rev-parse HEAD`.strip
      write_and_commit(base, "knowledge/n.md", "v2\n", "update")

      out = KiHistory.show("knowledge/n.md", sha)
      assert_equal "v1\n", out
    end
  end

  test "show returns empty string on unknown revision" do
    with_isolated_miolimos_base do
      assert_equal "", KiHistory.show("knowledge/missing.md", "deadbeef")
    end
  end

  test "diff returns the unified-diff text for the commit" do
    with_isolated_miolimos_base do |base|
      write_and_commit(base, "knowledge/n.md", "first\n", "init")
      write_and_commit(base, "knowledge/n.md", "second\n", "rewrite")
      sha = `git -C #{base} rev-parse HEAD`.strip
      diff = KiHistory.diff("knowledge/n.md", sha)
      assert_includes diff, "-first"
      assert_includes diff, "+second"
    end
  end

  test "Commit#relative_age formats sub-minute, sub-hour, sub-day, days, dates" do
    fresh = KiHistory::Commit.new(sha: "a"*40, date: 30.seconds.ago,  author: "x", subject: "y")
    mins  = KiHistory::Commit.new(sha: "a"*40, date: 5.minutes.ago,   author: "x", subject: "y")
    hours = KiHistory::Commit.new(sha: "a"*40, date: 3.hours.ago,     author: "x", subject: "y")
    days  = KiHistory::Commit.new(sha: "a"*40, date: 5.days.ago,      author: "x", subject: "y")
    far   = KiHistory::Commit.new(sha: "a"*40, date: 60.days.ago,     author: "x", subject: "y")
    assert_equal "gerade eben", fresh.relative_age
    assert_equal "5 Min.",      mins.relative_age
    assert_equal "3 Std.",      hours.relative_age
    assert_equal "5 Tagen",     days.relative_age
    assert_match %r{\d{4}-\d{2}-\d{2}}, far.relative_age
  end
end
