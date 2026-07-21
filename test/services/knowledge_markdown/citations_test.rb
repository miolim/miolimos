require "test_helper"

class KnowledgeMarkdown::CitationsTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    @src = Source.create!(
      slug:          "smith-2020-test-#{SecureRandom.hex(3)}",
      title:         "Smith Test Article",
      csl_type:      "article-journal",
      issued_string: "2020",
      issued_date:   Date.new(2020, 1, 1),
      creator:       @hans
    )
  end

  test "resolve replaces [@slug] with an inline source link" do
    html = KnowledgeMarkdown::Citations.resolve("foo [@#{@src.slug}] bar")
    assert_match %r{<a href="/sources/#{@src.slug}"}, html
    assert_match %r{class="source-cite"}, html
    assert_match %r{title="Smith Test Article"}, html
  end

  test "resolve renders broken-citation for unknown slugs" do
    html = KnowledgeMarkdown::Citations.resolve("foo [@unknown-source] bar")
    assert_match %r{source-cite-broken}, html
    assert_match %r{\[@unknown-source\]}, html
  end

  test "resolve carries locator into the label and HTML" do
    html = KnowledgeMarkdown::Citations.resolve("foo [@#{@src.slug}, p. 42] bar")
    assert_match %r{p\. 42}, html
  end

  test "resolve is a no-op when there are no citations" do
    src = "no citation here"
    assert_equal src, KnowledgeMarkdown::Citations.resolve(src)
  end

  test "format_label uses author + year when both present" do
    @src.update!(issued_string: "2020", issued_date: Date.new(2020,1,1))
    ki = create_human
    grant(ki, "KnowledgeItem", %w[create])
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: ki, title: "Alice Smith", item_type: :person,
                                content: "")
      person.update!(first_name: "Alice", last_name: "Smith")
      SourceCreator.create!(source: @src, knowledge_item_uuid: person.uuid,
                            role: "author", position: 0)
      label = KnowledgeMarkdown::Citations.format_label(@src.reload, nil)
      assert_match %r{Alice Smith}, label
      assert_match %r{2020}, label
    end
  end

  test "format_label falls back to year only when authors missing" do
    label = KnowledgeMarkdown::Citations.format_label(@src, nil)
    assert_equal "(2020)", label
  end
end
