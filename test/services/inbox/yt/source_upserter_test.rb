require "test_helper"

class Inbox::Yt::SourceUpserterTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Source",        %w[read create update delete])
    @url  = "https://www.youtube.com/watch?v=abc123"
  end

  test "creates Source with yt-<id> slug and motion_picture csl_type" do
    s = Inbox::Yt::SourceUpserter.call(
      { "id" => "abc123", "title" => "T", "uploader" => "Kanal",
        "upload_date" => "20240601", "description" => "Hi" },
      @url, actor: @hans
    )
    assert_equal "yt-abc123",       s.slug
    assert_equal "motion_picture",  s.csl_type
    assert_equal "T",                s.title
    assert_equal "Kanal",            s.publisher
    assert_equal Date.new(2024,6,1), s.issued_date
    assert_equal @url,               s.url
  end

  test "second call with same id is idempotent (same record)" do
    meta = { "id" => "abc", "title" => "X" }
    s1 = Inbox::Yt::SourceUpserter.call(meta, @url, actor: @hans)
    s2 = Inbox::Yt::SourceUpserter.call(meta, @url, actor: @hans)
    assert_equal s1.id, s2.id
  end

  test "#201: channel owner is linked as Organization-KI author" do
    s = Inbox::Yt::SourceUpserter.call(
      { "id" => "ch1", "title" => "T", "uploader" => "Sequoia Capital" },
      @url, actor: @hans
    )
    assert_equal 1, s.source_creators.count
    sc = s.source_creators.first
    assert_equal "author", sc.role
    ki = sc.knowledge_item
    assert_equal "Sequoia Capital", ki.title
    assert ki.organization?, "expected organization KI, got #{ki.item_type}"
  end

  test "#201: re-import does not duplicate source_creators" do
    meta = { "id" => "ch2", "title" => "T", "uploader" => "Veritasium" }
    Inbox::Yt::SourceUpserter.call(meta, @url, actor: @hans)
    Inbox::Yt::SourceUpserter.call(meta, @url, actor: @hans)
    s = Source.find_by(slug: "yt-ch2")
    assert_equal 1, s.source_creators.count
  end

  test "#201: existing Organization-KI is reused, no duplicate" do
    existing = FileProxy.create(actor: @hans, title: "Existing Channel",
                                 item_type: :organization, content: "")
    s = Inbox::Yt::SourceUpserter.call(
      { "id" => "ch3", "title" => "T", "uploader" => "Existing Channel" },
      @url, actor: @hans
    )
    assert_equal existing.uuid, s.source_creators.first.knowledge_item_uuid
    assert_equal 1, KnowledgeItem.organizations.where("lower(title) = ?", "existing channel").count
  end

  test "returns nil when video id is missing" do
    assert_nil Inbox::Yt::SourceUpserter.call({ "id" => "" }, @url, actor: @hans)
  end

  test "parse_date returns Date or nil for garbage" do
    assert_equal Date.new(2024, 6, 15), Inbox::Yt::SourceUpserter.parse_date("20240615")
    assert_nil Inbox::Yt::SourceUpserter.parse_date(nil)
    assert_nil Inbox::Yt::SourceUpserter.parse_date("xyz")
  end
end
