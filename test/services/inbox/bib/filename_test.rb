require "test_helper"

class Inbox::Bib::FilenameTest < ActiveSupport::TestCase
  def item_with(name)
    InboxItem.new(payload: { "original_filename" => name })
  end

  test "Doe_2024_Climate.pdf zerlegt in Family/Year/Title" do
    out = Inbox::Bib::Filename.call(item: item_with("Doe_2024_Climate.pdf"))
    assert_equal "Climate", out[:title]
    assert_equal Date.new(2024, 1, 1), out[:issued_date]
    assert_equal [{ given: nil, family: "Doe" }], out[:authors]
  end

  test "Dash-Separator: 'Doe - 2024 - Climate Change.pdf'" do
    out = Inbox::Bib::Filename.call(item: item_with("Doe - 2024 - Climate Change.pdf"))
    assert_equal "Doe", out[:authors].first[:family]
    assert_equal "Climate Change", out[:title]
  end

  test "camelCase: 'Doe2024Climate.pdf'" do
    out = Inbox::Bib::Filename.call(item: item_with("Doe2024Climate.pdf"))
    assert_equal "Doe", out[:authors].first[:family]
    assert_equal "Climate", out[:title]
  end

  test "kein Jahr → ganzer Filename als Title, keine Authoren" do
    out = Inbox::Bib::Filename.call(item: item_with("just_a_title.pdf"))
    assert_equal "just a title", out[:title]
    assert_equal [], out[:authors]
  end

  test "external_path-Fallback wenn kein original_filename im Payload" do
    item = InboxItem.new(external_path: "/tmp/.uploads/2026-05-10/abc-Doe_2024_Climate.pdf")
    out = Inbox::Bib::Filename.call(item: item)
    assert_match(/Climate/, out[:title])
  end
end
