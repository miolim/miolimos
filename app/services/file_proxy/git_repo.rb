# Git-Commit-Wrapper für FileProxy. Macht `git add` + `git commit` im
# Daten-Repo (BASE_PATH) mit Actor-Identität. Aus file_proxy.rb (#127)
# ausgelagert, damit der einzige Berührungspunkt mit `system("git", …)`
# klar lokalisiert ist.
class FileProxy
  module GitRepo
    module_function

    def commit(actor:, file_path:, message:)
      author_name  = actor.name
      author_email = actor.email || "#{actor.name.parameterize}@miolimos.local"
      quiet = Rails.env.test? ? [:out, :err] : :err
      paths = Array(file_path)
      Dir.chdir(FileProxy::BASE_PATH) do
        system("git", "add", *paths, quiet => "/dev/null")
        system(
          {
            "GIT_AUTHOR_NAME"     => author_name,
            "GIT_AUTHOR_EMAIL"    => author_email,
            "GIT_COMMITTER_NAME"  => "miolimOS",
            "GIT_COMMITTER_EMAIL" => "system@miolimos.local"
          },
          "git", "commit", "-q", "-m", message,
          quiet => "/dev/null"
        )
      end
    rescue => e
      Rails.logger.warn("Git commit failed: #{e.message}")
    end
  end
end
