require "test_helper"

# #378 Phase 5 (Hans, 2026-05-26): Tests fuer Source — bisher
# komplett ohne Model-Test (193 LoC mit Business-Rules, hohes Risiko).
class SourceTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  # --- Validations ---

  test "valid Source roundtrips" do
    src = Source.create!(slug: "valid-1", title: "Test", csl_type: "book", creator: @hans)
    assert src.persisted?
  end

  test "requires title" do
    src = Source.new(slug: "no-title", csl_type: "book", creator: @hans)
    assert_not src.valid?
    assert_includes src.errors[:title], "muss ausgefüllt werden"
  end

  test "rejects invalid csl_type" do
    src = Source.new(slug: "x", title: "T", csl_type: "novel", creator: @hans)
    assert_not src.valid?
    assert src.errors[:csl_type].any?
  end

  test "rejects invalid slug format" do
    src = Source.new(slug: "Bad Slug!", title: "T", csl_type: "book", creator: @hans)
    assert_not src.valid?
    assert src.errors[:slug].any?
  end

  test "allows slug with dots and underscores" do
    src = Source.create!(slug: "smith.doe_2020", title: "T", csl_type: "book", creator: @hans)
    assert src.persisted?
  end

  test "rejects duplicate slug" do
    Source.create!(slug: "dup-1", title: "A", csl_type: "book", creator: @hans)
    src = Source.new(slug: "dup-1", title: "B", csl_type: "book", creator: @hans)
    assert_not src.valid?
    assert src.errors[:slug].any?
  end

  # --- Auto-Slug-Generation ---

  test "generates slug from title when blank" do
    src = Source.create!(title: "Manifesto", csl_type: "book", creator: @hans)
    assert_match(/manifesto/, src.slug)
  end

  test "keeps explicit slug when provided" do
    src = Source.create!(slug: "my-custom", title: "Anything", csl_type: "book", creator: @hans)
    assert_equal "my-custom", src.slug
  end

  test "auto-slug appends suffix on conflict" do
    Source.create!(slug: "samebase", title: "Samebase", csl_type: "book", creator: @hans)
    src = Source.create!(title: "Samebase", csl_type: "book", creator: @hans)
    assert_not_equal "samebase", src.slug
    assert_match(/samebase/, src.slug)
  end

  # --- display_year ---

  test "display_year prefers issued_date year" do
    src = Source.create!(slug: "yd1", title: "T", csl_type: "book", creator: @hans,
                          issued_date: Date.new(2018, 4, 1))
    assert_equal "2018", src.display_year
  end

  test "display_year falls back to first 4-digit in issued_string" do
    src = Source.create!(slug: "yd2", title: "T", csl_type: "book", creator: @hans,
                          issued_string: "Frühjahr 1997, überarbeitete Auflage 2003")
    assert_equal "1997", src.display_year
  end

  test "display_year returns nil when no date present" do
    src = Source.create!(slug: "yd3", title: "T", csl_type: "book", creator: @hans)
    assert_nil src.display_year
  end

  # --- to_csl_json ---

  test "to_csl_json roundtrips core fields" do
    src = Source.create!(slug: "csl1", title: "Book Title", csl_type: "book",
                          creator: @hans, publisher: "Pub", url: "https://ex.org/x",
                          issued_date: Date.new(2020, 6, 15))
    csl = src.to_csl_json
    assert_equal "csl1", csl["id"]
    assert_equal "book", csl["type"]
    assert_equal "Book Title", csl["title"]
    assert_equal "Pub", csl["publisher"]
    assert_equal "https://ex.org/x", csl["URL"]
    assert_equal [[2020, 6, 15]], csl["issued"]["date-parts"]
  end

  test "to_csl_json drops nil fields" do
    src = Source.create!(slug: "csl2", title: "T", csl_type: "book", creator: @hans)
    csl = src.to_csl_json
    refute csl.key?("publisher")
    refute csl.key?("URL")
  end

  test "to_csl_json renders issued_string as raw when no issued_date" do
    src = Source.create!(slug: "csl3", title: "T", csl_type: "book", creator: @hans,
                          issued_string: "spring 1999")
    csl = src.to_csl_json
    assert_equal({ "raw" => "spring 1999" }, csl["issued"])
  end

  # --- identifier_value ---

  test "identifier_value returns nil when scheme not present" do
    src = Source.create!(slug: "id1", title: "T", csl_type: "book", creator: @hans)
    assert_nil src.identifier_value("DOI")
  end

  test "identifier_value returns matching identifier value" do
    src = Source.create!(slug: "id2", title: "T", csl_type: "book", creator: @hans)
    SourceIdentifier.create!(source: src, scheme: "DOI", value: "10.1234/abc")
    assert_equal "10.1234/abc", src.identifier_value("DOI")
  end

  # --- display_authors ---

  test "display_authors lists up to 3 authors and adds et al. for more" do
    src = Source.create!(slug: "da1", title: "T", csl_type: "book", creator: @hans)
    %w[Aaa Bbb Ccc Ddd].each_with_index do |last, i|
      ki = FileProxy.create(actor: @hans, title: "#{last} #{last}", item_type: :person, content: "x")
      ki.update!(first_name: last, last_name: last)
      SourceCreator.create!(source: src, knowledge_item_uuid: ki.uuid,
                              role: "author", position: i)
    end
    out = src.display_authors
    assert_match(/et al\./, out)
  end

  test "display_authors returns empty when no creators" do
    src = Source.create!(slug: "da2", title: "T", csl_type: "book", creator: @hans)
    assert_equal "", src.display_authors
  end

  # --- display_authors_list (CSL-Style) ---

  test "display_authors_list uses Nachname, Vorname format for persons" do
    src = Source.create!(slug: "dal1", title: "T", csl_type: "book", creator: @hans)
    ki = FileProxy.create(actor: @hans, title: "Anna Bauer", item_type: :person, content: "")
    ki.update!(first_name: "Anna", last_name: "Bauer")
    SourceCreator.create!(source: src, knowledge_item_uuid: ki.uuid, role: "author")
    assert_equal "Bauer, Anna", src.display_authors_list
  end

  test "display_authors_list joins multiple authors with pipe" do
    src = Source.create!(slug: "dal2", title: "T", csl_type: "book", creator: @hans)
    [["A", "Aaa"], ["B", "Bbb"]].each do |first, last|
      ki = FileProxy.create(actor: @hans, title: "#{first} #{last}", item_type: :person, content: "")
      ki.update!(first_name: first, last_name: last)
      SourceCreator.create!(source: src, knowledge_item_uuid: ki.uuid, role: "author")
    end
    assert_includes src.display_authors_list, "Aaa, A"
    assert_includes src.display_authors_list, "Bbb, B"
    assert_includes src.display_authors_list, " | "
  end
end
