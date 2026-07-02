require "test_helper"

# #650: FileProxy.update auf Binär-Datei-KIs (Bild/PDF) darf das Asset
# nie mit Frontmatter-Text überschreiben — Umbenennung verschiebt die
# Datei byte-identisch und pflegt den Sidecar.
class FileProxyBinaryUpdateTest < ActiveSupport::TestCase
  GIF = "GIF89a\x01\x00\x01\x00\x80\x00\x00\xFF\xFF\xFF\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".b

  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-bin-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    grant(@hans, "KnowledgeItem", %w[read create update])
  end

  test "Umbenennung einer Bild-KI verschiebt das Binärfile unversehrt + rewritet Embeds" do
    with_isolated_miolimos_base do
      io = StringIO.new(GIF)
      def io.original_filename = "foto.gif"
      ki = FileProxy.create_with_file(actor: @hans, title: "Foto Alt",
                                      uploaded_io: io, item_type: :image)
      assert ki.file_path.end_with?(".gif")

      # Ein KI bettet das Bild ein — Embed muss die Umbenennung überleben.
      embedder = FileProxy.create(actor: @hans, title: "Album", item_type: :note,
                                  content: "Hier: ![[Foto Alt]] und Link [[Foto Alt]].")

      FileProxy.update(actor: @hans, knowledge_item: ki, title: "Foto Neu")
      ki.reload

      assert_equal "Foto Neu", ki.title
      assert ki.file_path.end_with?(".gif"), "Endung muss erhalten bleiben (war: #{ki.file_path})"
      full = FileProxy::BASE_PATH.join(ki.file_path)
      assert File.exist?(full)
      assert_equal GIF, File.binread(full), "Binärinhalt muss byte-identisch bleiben"
      assert File.exist?("#{full}.meta.yml"), "Sidecar fehlt"
      assert_includes File.read("#{full}.meta.yml"), "Foto Neu"

      # Embeds + Links rewritten (#651 — gilt auch für ![[…]]).
      embedder.reload
      assert_includes embedder.body, "![[Foto Neu]]"
      assert_includes embedder.body, "[[Foto Neu]]"
      refute_includes embedder.body, "Foto Alt"
    end
  end

  test "Update ohne Titelwechsel schreibt nur den Sidecar, nie das Asset" do
    with_isolated_miolimos_base do
      io = StringIO.new(GIF)
      def io.original_filename = "foto.gif"
      ki = FileProxy.create_with_file(actor: @hans, title: "Foto Stabil",
                                      uploaded_io: io, item_type: :image)
      FileProxy.update(actor: @hans, knowledge_item: ki, tags: ["album"])
      ki.reload
      assert_equal GIF, File.binread(FileProxy::BASE_PATH.join(ki.file_path))
      assert_includes ki.tags, "album"
    end
  end
end
