require "test_helper"

class Inbox::Bib::SourceMatcherTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Source",        %w[read create update delete])
  end

  test "Identifier-Match (DOI, case-insensitive)" do
    src = Source.create!(slug: "doe-2024-x", csl_type: "article-journal",
                         title: "X", creator: @hans)
    src.source_identifiers.create!(scheme: "DOI", value: "10.1234/abc")

    found = Inbox::Bib::SourceMatcher.find(identifier: { scheme: "DOI", value: "10.1234/ABC" })
    assert_equal src.id, found.id
  end

  test "Identifier-Match (ISBN) ist gegen DOI-Match isoliert" do
    Source.create!(slug: "a-doi", csl_type: "article-journal", title: "A", creator: @hans)
      .source_identifiers.create!(scheme: "DOI", value: "10.1234/y")
    isbn_src = Source.create!(slug: "a-isbn", csl_type: "book", title: "B", creator: @hans)
    isbn_src.source_identifiers.create!(scheme: "ISBN", value: "9780306406157")

    found = Inbox::Bib::SourceMatcher.find(identifier: { scheme: "ISBN", value: "9780306406157" })
    assert_equal isbn_src.id, found.id
  end

  test "Title+First-Author-Family-Match wenn Identifier fehlt" do
    with_isolated_miolimos_base do
      author = nil
      src = nil
      Current.set(actor: @hans) do
        author = FileProxy.create(actor: @hans, title: "Jane Doe", item_type: :person, content: "")
        author.update!(first_name: "Jane", last_name: "Doe")
        src = Source.create!(slug: "doe-2024-climate", csl_type: "article-journal",
                             title: "Climate Change is Real", creator: @hans)
        src.source_creators.create!(knowledge_item_uuid: author.uuid, role: "author", position: 0)
      end

      result = {
        identifier: nil,
        title:      "Climate Change Is Real",
        authors:    [{ given: "Jane", family: "Doe" }]
      }
      found = Inbox::Bib::SourceMatcher.find(result)
      assert_equal src.id, found.id
    end
  end

  test "Title-Match ohne Author → kein Treffer" do
    Source.create!(slug: "x-2024", csl_type: "article-journal",
                   title: "Some Title", creator: @hans)
    result = { identifier: nil, title: "Some Title", authors: [] }
    assert_nil Inbox::Bib::SourceMatcher.find(result)
  end

  test "Title gleich, aber Author anders → kein Treffer" do
    with_isolated_miolimos_base do
      Current.set(actor: @hans) do
        a1 = FileProxy.create(actor: @hans, title: "Jane Doe", item_type: :person, content: "")
        a1.update!(last_name: "Doe")
        src = Source.create!(slug: "doe-x", csl_type: "article-journal", title: "Sometitle", creator: @hans)
        src.source_creators.create!(knowledge_item_uuid: a1.uuid, role: "author", position: 0)

        result = { identifier: nil, title: "Sometitle", authors: [{ family: "Smith" }] }
        assert_nil Inbox::Bib::SourceMatcher.find(result)
      end
    end
  end
end
