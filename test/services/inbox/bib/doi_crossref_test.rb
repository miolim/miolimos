require "test_helper"

class Inbox::Bib::DoiCrossrefTest < ActiveSupport::TestCase
  test "extract_doi findet DOI auch mit trailing-Punkt" do
    assert_equal "10.1234/foo-bar",
                 Inbox::Bib::DoiCrossref.extract_doi("see https://doi.org/10.1234/foo-bar.")
  end

  test "extract_doi nil ohne DOI" do
    assert_nil Inbox::Bib::DoiCrossref.extract_doi("nothing here")
  end

  test "normalize mappt CrossRef-Journal-Article auf article-journal" do
    meta = {
      "title" => ["A Paper"], "container-title" => ["J. of X"], "publisher" => "P",
      "type"  => "journal-article", "volume" => "1", "issue" => "2", "page" => "10-20",
      "issued" => { "date-parts" => [[2023, 5, 7]] },
      "author" => [{ "given" => "A", "family" => "B" }]
    }
    out = Inbox::Bib::DoiCrossref.normalize(meta, doi: "10.1/x")
    assert_equal "article-journal", out[:csl_type]
    assert_equal "A Paper", out[:title]
    assert_equal Date.new(2023, 5, 7), out[:issued_date]
    assert_equal "DOI", out[:identifier][:scheme]
    assert_equal "10.1/x", out[:identifier][:value]
    assert_equal [{ given: "A", family: "B" }], out[:authors]
  end

  test "normalize fällt auf published-online / created zurück, wenn print fehlt" do
    meta = {
      "title" => ["X"], "type" => "posted-content",
      "published-online" => { "date-parts" => [[2024, 1]] },
      "author" => []
    }
    out = Inbox::Bib::DoiCrossref.normalize(meta, doi: "10.1/y")
    assert_equal "manuscript", out[:csl_type]
    assert_equal Date.new(2024, 1, 1), out[:issued_date]
  end
end
