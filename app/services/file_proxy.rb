require "digest"
require "fileutils"
require "pathname"

# Datei-zentrierte Persistenz fuer Knowledge-Items. Jeder Aufruf hier
# ist ein Hot-Path: KI-Anlage, Save, Move, Delete + Sub-Workflows wie
# Append-Session und Frontmatter-Merge.
#
# Innenleben in fokussierte Module gesplittet (siehe `file_proxy/`):
#   - Reader   — read, read_body, read_frontmatter_yaml
#   - Writer   — create, create_with_file, update, append_session
#   - Trash    — destroy, restore, purge!
#   - Metadata — merge_frontmatter!
# Die Module sind via `extend` ins FileProxy-Singleton gehievt, sodass
# alle Caller `FileProxy.read(...)` etc. unveraendert nutzen. Direkt-
# Aufruf `FileProxy::Reader.read(...)` ginge auch.
class FileProxy
  BASE_PATH = Pathname.new(ENV.fetch("MIOLIMOS_DATA_PATH", File.expand_path("~/miolimos")))

  class FileNotFound < StandardError; end
end

require_relative "file_proxy/paths"
require_relative "file_proxy/frontmatter"
require_relative "file_proxy/git_repo"
require_relative "file_proxy/reader"
require_relative "file_proxy/writer"
require_relative "file_proxy/trash"
require_relative "file_proxy/metadata"

class FileProxy
  extend Reader
  extend Writer
  extend Trash
  extend Metadata
end
