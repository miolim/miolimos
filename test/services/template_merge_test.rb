require "test_helper"

# #941: direkter Unit-Test für den {{key}}-Merge (#926 Stufe 2) — vorher nur
# indirekt über Modell-/Controller-Strecken abgedeckt.
class TemplateMergeTest < ActiveSupport::TestCase
  CTX = { "kaltmiete" => "850,00 €", "mieter name" => "Erika Muster" }.freeze

  test "ersetzt Platzhalter case-insensitiv und whitespace-tolerant" do
    assert_equal "Miete: 850,00 €", TemplateMerge.merge("Miete: {{Kaltmiete}}", CTX)
    assert_equal "850,00 €", TemplateMerge.merge("{{ kaltmiete }}", CTX)
    assert_equal "Erika Muster", TemplateMerge.merge("{{Mieter  Name}}", CTX)
  end

  test "unaufgelöste Platzhalter bleiben LITERAL stehen (nichts verschwindet still)" do
    assert_equal "Kaution: {{kaution}}", TemplateMerge.merge("Kaution: {{kaution}}", CTX)
  end

  test "unresolved listet nur die fehlenden Keys, keys alle (unique)" do
    text = "{{kaltmiete}} und {{kaution}} und nochmal {{kaution}}"
    assert_equal %w[kaution], TemplateMerge.unresolved(text, CTX)
    assert_equal %w[kaltmiete kaution], TemplateMerge.keys(text)
  end

  test "robust bei leerem Text/Kontext und nil-Werten" do
    assert_equal "", TemplateMerge.merge(nil, CTX)
    assert_equal "{{x}}", TemplateMerge.merge("{{x}}", {})
    assert_equal "{{x}}", TemplateMerge.merge("{{x}}", { "x" => nil })
  end

  test "mehrzeilige Klammern sind KEINE Platzhalter" do
    text = "{{kein\nplatzhalter}}"
    assert_equal text, TemplateMerge.merge(text, CTX)
  end
end
