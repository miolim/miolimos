require "test_helper"

class BadgesHelperTest < ActionView::TestCase
  test "priority_dot returns a span with color class and title" do
    html = priority_dot("urgent")
    assert_includes html, "bg-rose-500"
    assert_includes html, "title="
  end

  test "priority_dot falls back to slate-400 for unknown value" do
    html = priority_dot("unknown")
    assert_includes html, "bg-slate-400"
  end

  test "status_badge uses emerald tone for done" do
    labels = { "done" => "Erledigt", "open" => "Offen" }
    html = status_badge("done", labels: labels)
    assert_includes html, "bg-emerald-100"
    assert_includes html, "Erledigt"
  end

  test "status_pill nimmt Fallback für unbekannten Status" do
    html = status_pill("zappa")
    assert_includes html, "bg-slate-100"
    assert_includes html, "zappa"
  end

  test "priority_badge gibt unterschiedliche Töne pro Wert" do
    labels = { "urgent" => "Dringend", "high" => "Hoch", "normal" => "Normal", "low" => "Niedrig" }
    assert_includes priority_badge("urgent", labels: labels), "bg-rose-100"
    assert_includes priority_badge("high",   labels: labels), "bg-orange-100"
    assert_includes priority_badge("normal", labels: labels), "bg-slate-100"
    assert_includes priority_badge("low",    labels: labels), "bg-slate-50"
  end
end
