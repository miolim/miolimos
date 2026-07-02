require "test_helper"

class InboxItemTest < ActiveSupport::TestCase
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-ibm-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
  end

  def item_for(url)
    InboxItem.new(creator: @hans, source_kind: "web_url", source_url: url)
  end

  # #618 v4: Video-ID-Extraktion fürs Thumbnail.
  test "youtube_video_id erkennt watch-, youtu.be- und shorts-URLs" do
    assert_equal "dQw4w9WgXcQ", item_for("https://www.youtube.com/watch?v=dQw4w9WgXcQ").youtube_video_id
    assert_equal "dQw4w9WgXcQ", item_for("https://m.youtube.com/watch?t=8s&v=dQw4w9WgXcQ&pp=x").youtube_video_id
    assert_equal "dQw4w9WgXcQ", item_for("https://youtu.be/dQw4w9WgXcQ").youtube_video_id
    assert_equal "0zqmlklcY-U", item_for("https://www.youtube.com/shorts/0zqmlklcY-U").youtube_video_id
    assert_nil item_for("https://vimeo.com/123456").youtube_video_id
    assert_nil item_for(nil).youtube_video_id
  end
end
