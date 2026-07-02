require "test_helper"

# #670: Dublettenkontrolle beim Import.
class InboxItemDuplicateTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
  end

  def ki_for_source(src, title)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title, item_type: :transcript,
                          file_path: "x/#{SecureRandom.hex(3)}.md", content_hash: "h",
                          body: "", bib_source_id: src.id)
  end

  test "YouTube: gleiche Video-ID über Source-Slug erkannt — auch bei youtu.be/shorts" do
    src = Source.create!(slug: "yt-abc123xyz", title: "Video", csl_type: "motion_picture", creator: @hans)
    dupe_ki = ki_for_source(src, "Transkript Video")

    %w[
      https://www.youtube.com/watch?v=abc123xyz
      https://youtu.be/abc123xyz
      https://www.youtube.com/shorts/abc123xyz
      https://m.youtube.com/watch?t=8s&v=abc123xyz
    ].each do |url|
      item = InboxItem.new(creator: @hans, source_kind: "youtube_url", source_url: url)
      assert_equal [dupe_ki.uuid], item.potential_duplicate_kis.pluck(:uuid), "für #{url}"
      assert item.potential_duplicate?
    end
  end

  test "YouTube: Erkennung auch über den YouTube-Identifier (anderer Slug)" do
    src = Source.create!(slug: "manuell-umbenannt", title: "V", csl_type: "motion_picture", creator: @hans)
    src.source_identifiers.create!(scheme: "YouTube", value: "vid99999")
    ki = ki_for_source(src, "T")
    item = InboxItem.new(creator: @hans, source_kind: "youtube_url",
                         source_url: "https://www.youtube.com/watch?v=vid99999")
    assert_equal [ki.uuid], item.potential_duplicate_kis.pluck(:uuid)
  end

  test "web_url: Dublette über exakte source_url der Quelle" do
    src = Source.create!(slug: "web-1", title: "Artikel", csl_type: "webpage",
                         url: "https://example.com/x", creator: @hans)
    ki = ki_for_source(src, "Clip")
    item = InboxItem.new(creator: @hans, source_kind: "web_url", source_url: "https://example.com/x")
    assert_equal [ki.uuid], item.potential_duplicate_kis.pluck(:uuid)
  end

  test "keine Quelle / unbekannte URL → keine Dublette" do
    item = InboxItem.new(creator: @hans, source_kind: "web_url", source_url: "https://nope.example/y")
    refute item.potential_duplicate?
    assert_empty item.potential_duplicate_kis
  end
end
