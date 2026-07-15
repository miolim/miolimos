require "test_helper"

# #995: Portoprodukte + Dummy-Marke (Layout-Test ohne Portokasse).
class InternetmarkeTest < ActiveSupport::TestCase
  test "product findet Produkte per Code (auch als String)" do
    assert_equal "Standardbrief", Internetmarke.product("1")[:label]
    assert_equal 95, Internetmarke.product(1)[:cents]
    assert_nil Internetmarke.product(999)
  end

  test "Dummy-Marke ist deutlich als MUSTER gekennzeichnet" do
    svg = Internetmarke::DummyStamp.svg(Internetmarke.product(1))
    assert_includes svg, "MUSTER"
    assert_includes svg, "NICHT GÜLTIG"
    assert_includes svg, "0,95 EUR"
    refute_includes svg, "Deutsche Post"   # kein Post-Branding auf dem Muster
  end

  test "data_uri liefert einbettbares SVG" do
    uri = Internetmarke::DummyStamp.data_uri(Internetmarke.product(21))
    assert uri.start_with?("data:image/svg+xml;base64,")
    decoded = Base64.strict_decode64(uri.split(",", 2).last).force_encoding("UTF-8")
    assert_includes decoded, "Großbrief"
  end
end
