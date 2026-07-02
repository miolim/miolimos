require "test_helper"

# #609 v2: Bild-Upload in der Inbox → Bild-KI (vorher fraß MarkdownToKi
# das Binärfile und starb an "invalid byte sequence in UTF-8").
class ImageToKiTest < ActiveSupport::TestCase
  # 1×1-GIF (binär, enthält ungültige UTF-8-Bytes).
  GIF = "GIF89a\x01\x00\x01\x00\x80\x00\x00\xFF\xFF\xFF\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;".b

  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-img-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    grant(@hans, "KnowledgeItem", %w[read create update])
    @file = Tempfile.create(["treppe", ".gif"])
    File.binwrite(@file.path, GIF)
    @item = InboxItem.create!(creator: @hans, source_kind: "upload",
                              external_path: @file.path, title: "Foto Treppe Test",
                              payload: { "content_type" => "image/gif",
                                         "original_filename" => "treppe.gif" })
  end

  teardown do
    File.delete(@file.path) if File.exist?(@file.path)
  end

  test "applies? erkennt Bilder, MarkdownToKi lehnt sie ab; suggested ist image_to_ki" do
    assert Inbox::Processors::ImageToKi.applies?(@item)
    refute Inbox::Processors::MarkdownToKi.applies?(@item)
    assert_equal "image_to_ki", @item.suggested_processor_kind
  end

  test "process! legt Bild-KI an (Binärdatei, Topics geerbt)" do
    with_isolated_miolimos_base do
      topic = Topic.create!(name: "Bild-Thema", slug: "bild-#{SecureRandom.hex(3)}", creator: @hans)
      @item.topics << topic

      assert Inbox::Processors::ImageToKi.run(@item, actor: @hans)
      ki = KnowledgeItem.find_by!(title: "Foto Treppe Test")
      assert_equal "image", ki.item_type   # #609 v3: eigener Typ
      assert ki.file_path.end_with?(".gif")
      assert_equal [topic.id], ki.topics.pluck(:id)
      assert_equal "GIF89a", File.binread(FileProxy::BASE_PATH.join(ki.file_path))[0, 6]
      assert_equal "processed", @item.reload.status
    end
  end

  test "MarkdownToKi weist Binärdateien mit klarer Meldung ab (kein invalid byte sequence)" do
    @item.payload["content_type"] = "application/octet-stream"
    err = assert_raises(RuntimeError) do
      Inbox::Processors::MarkdownToKi.new.send(:read_raw,
        InboxItem.new(creator: @hans, source_kind: "upload", external_path: @file.path))
    end
    assert_includes err.message, "Binärinhalt"
  end
end
