require "test_helper"

class SourceCitationsTest < ActiveSupport::TestCase
  setup { @hans = create_human }

  test "collects sources cited via [@slug] and [[&slug]], deduped" do
    s1 = Source.create!(slug: "bjork_1994_a", title: "Memory", csl_type: "book", creator: @hans)
    s2 = Source.create!(slug: "cepeda_2006_a", title: "Spacing", csl_type: "article-journal", creator: @hans)
    ki = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "N", item_type: "note",
      body: "Erst [@bjork_1994_a], dann [[&cepeda_2006_a]] und nochmal [@bjork_1994_a].",
      file_path: "k/#{SecureRandom.hex(4)}.md", content_hash: SecureRandom.hex(32))

    found = SourceCitations.for(ki)
    assert_equal [s1.id, s2.id].sort, found.map(&:id).sort
    assert_equal 2, found.size, "dedupes repeated citations"
  end

  test "returns empty for a body without citations" do
    ki = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "N2", item_type: "note",
      body: "Kein Zitat hier.", file_path: "k/#{SecureRandom.hex(4)}.md", content_hash: SecureRandom.hex(32))
    assert_empty SourceCitations.for(ki)
  end
end
