require "test_helper"

class KnowledgeMarkdown::ExternalLinksTest < ActiveSupport::TestCase
  test "annotate adds target=_blank and an external icon to http links" do
    html = '<a href="https://example.com">site</a>'
    out  = KnowledgeMarkdown::ExternalLinks.annotate(html)
    assert_match %r{target="_blank"}, out
    assert_match %r{rel="noopener"},  out
    assert_match %r{<svg }, out
  end

  test "annotate decorates mailto links the same way" do
    html = '<a href="mailto:hans@example.com">mail</a>'
    out  = KnowledgeMarkdown::ExternalLinks.annotate(html)
    assert_match %r{target="_blank"}, out
  end

  test "annotate leaves own-host links untouched (no target, no icon)" do
    html = '<a href="https://os.miolim.de/tasks/1">task</a>'
    out  = KnowledgeMarkdown::ExternalLinks.annotate(html)
    refute_includes out, "target="
    refute_includes out, "<svg "
  end

  test "annotate respects a pre-set target attribute and does not duplicate" do
    html = '<a href="https://example.com" target="_self">x</a>'
    out  = KnowledgeMarkdown::ExternalLinks.annotate(html)
    # exactly one target= occurrence
    assert_equal 1, out.scan(/target=/).size
  end

  test "annotate returns html_safe content" do
    out = KnowledgeMarkdown::ExternalLinks.annotate('<a href="https://example.com">x</a>')
    assert out.html_safe?
  end
end
