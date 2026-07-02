require "test_helper"

class CommitmentsHelperTest < ActionView::TestCase
  test "commitment_meta liefert Hash mit Icon, Label, Color" do
    today = commitment_meta("today")
    assert_equal "today",          today[:key]
    assert_equal "Heute",          today[:label]
    assert_equal "text-emerald-600", today[:color]
  end

  test "commitment_meta fällt auf inbox für nil/unbekannt" do
    assert_equal "inbox", commitment_meta(nil)[:key]
    assert_equal "inbox", commitment_meta("garbage")[:key]
  end
end
