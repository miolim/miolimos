require "open3"

# Liest den git-log + diff einer KI-Markdown-Datei (oder beliebigen
# Datei im Daten-Repo unter ~/miolimos/) und stellt die Versionshistorie
# bereit. KI-Saves committen automatisch via FileProxy.git_commit, also
# ist hier nichts zusätzlich zu pflegen — die Historie ist immer da.
#
# Renames werden mit `--follow` verfolgt, damit Title-Wechsel die
# History nicht zerschneidet.
class KiHistory
  Commit = Struct.new(:sha, :date, :author, :subject, keyword_init: true) do
    def short_sha = sha[0, 8]
    def relative_age
      seconds = Time.current - date
      case seconds
      when 0..59             then "gerade eben"
      when 60..3599          then "#{(seconds / 60).to_i} Min."
      when 3600..86_399      then "#{(seconds / 3600).to_i} Std."
      when 86_400..2_591_999 then "#{(seconds / 86_400).to_i} Tagen"
      else date.strftime("%Y-%m-%d")
      end
    end
  end

  def self.for_path(rel_path, limit: 50)
    new(rel_path).log(limit: limit)
  end

  def self.show(rel_path, sha)
    new(rel_path).show(sha)
  end

  def self.diff(rel_path, sha)
    new(rel_path).diff(sha)
  end

  def initialize(rel_path)
    @rel_path = rel_path.to_s
  end

  # Liefert Commit-Liste (neueste zuerst). `--follow` verfolgt Renames;
  # Format `<sha>%x09<iso-date>%x09<author>%x09<subject>` mit Tabs als
  # Separator (Tab tritt in Subjects praktisch nie auf).
  def log(limit: 50)
    return [] if @rel_path.empty?
    out = git("log", "--follow",
              "--pretty=format:%H%x09%aI%x09%an%x09%s",
              "-n", limit.to_s, "--", @rel_path)
    out.lines.map do |line|
      sha, iso, author, subject = line.chomp.split("\t", 4)
      next nil if sha.nil?
      Commit.new(sha: sha, date: Time.parse(iso), author: author, subject: subject)
    end.compact
  rescue => e
    Rails.logger.warn("KiHistory.log: #{e.class} #{e.message}")
    []
  end

  # Datei-Inhalt zur angegebenen Revision. Nutzt `git show <sha>:<path>`.
  # Bei Rename: man kann den damaligen Pfad in `path` mitgeben, sonst
  # liefert git eine Fehlermeldung.
  def show(sha, path: nil)
    git("show", "#{sha}:#{path || @rel_path}")
  rescue
    ""
  end

  # Unified diff von <sha>~ bis <sha> für die Datei.
  def diff(sha)
    git("show", "--no-color", "--unified=3", sha, "--", @rel_path)
  rescue
    ""
  end

  private

  def git(*args)
    out, err, status = Open3.capture3({}, "git", *args, chdir: FileProxy::BASE_PATH.to_s)
    raise "git #{args.first} failed: #{err.lines.first}" unless status.success?
    out
  end
end
