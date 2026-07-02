require "test_helper"

# #529 (Hans, 2026-06-06): SourceCreator-Modell-Vertrag (Validierungen,
# Identifizierungs-Lebenszyklus aus #516) war nur indirekt über Controller-/
# Service-Tests berührt — hier direkt abgesichert.
class SourceCreatorTest < ActiveSupport::TestCase
  setup do
    @hans   = create_human
    @source = Source.create!(title: "Studie", csl_type: "article-journal", creator: @hans)
    @person = person_ki("Erika Mustermann")
  end

  def person_ki(name)
    KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: name, item_type: :person,
      file_path: "knowledge/people/#{SecureRandom.hex(4)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current, file_updated_at: Time.current, indexed_at: Time.current
    )
  end

  def link(**overrides)
    SourceCreator.create!({ source: @source, knowledge_item_uuid: @person.uuid }.merge(overrides))
  end

  test "Default: neue Verknüpfung ist provisional mit Rolle author" do
    sc = link
    assert_predicate sc, :provisional?
    refute_predicate sc, :identified?
    assert_equal "author", sc.role
  end

  test "Validierung: Rolle muss in ROLES sein" do
    sc = SourceCreator.new(source: @source, knowledge_item_uuid: @person.uuid, role: "quatsch")
    refute_predicate sc, :valid?
    assert sc.errors.added?(:role, :inclusion, value: "quatsch")
  end

  test "Validierung: identification muss in IDENTIFICATIONS sein" do
    sc = SourceCreator.new(source: @source, knowledge_item_uuid: @person.uuid, identification: "halb")
    refute_predicate sc, :valid?
  end

  test "Validierung: confidence ist optional, aber wenn gesetzt eingeschränkt" do
    assert link(confidence: nil).valid?
    assert link(confidence: "wahrscheinlich").valid?
    bad = SourceCreator.new(source: @source, knowledge_item_uuid: @person.uuid, confidence: "99%")
    refute_predicate bad, :valid?
  end

  test "knowledge_item_uuid ist Pflicht" do
    sc = SourceCreator.new(source: @source, role: "author")
    refute_predicate sc, :valid?
    assert sc.errors.added?(:knowledge_item_uuid, :blank)
  end

  test "Scopes trennen provisional und identified" do
    prov = link
    idn  = link
    idn.identify!
    assert_includes SourceCreator.provisional, prov
    refute_includes SourceCreator.provisional, idn
    assert_includes SourceCreator.identified, idn
    refute_includes SourceCreator.identified, prov
  end

  test "identify! markiert als bestätigt mit Konfidenz und Provenienz" do
    sc = link
    sc.identify!(confidence: "bestätigt", via: "orcid", by: @hans)
    sc.reload
    assert_predicate sc, :identified?
    assert_equal "bestätigt", sc.confidence
    assert_equal "orcid",     sc.identified_via
    assert_equal @hans.id,    sc.identified_by_id
    assert_not_nil sc.identified_at
  end
end
