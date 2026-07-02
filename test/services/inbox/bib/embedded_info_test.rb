require "test_helper"

class Inbox::Bib::EmbeddedInfoTest < ActiveSupport::TestCase
  def stub_info(hash)
    orig = Inbox::Bib::EmbeddedInfo.method(:read_info)
    Inbox::Bib::EmbeddedInfo.define_singleton_method(:read_info) { |_p| hash }
    yield
  ensure
    Inbox::Bib::EmbeddedInfo.define_singleton_method(:read_info, orig)
  end

  test "verwertet Title + Author aus /Info" do
    stub_info("Title" => "Climate Change", "Author" => "John Doe, Jane Roe",
              "CreationDate" => "Mon Mar 15 12:34:56 2024 UTC",
              "Subject" => "Earth science research") do
      out = Inbox::Bib::EmbeddedInfo.call(path: "/tmp/x.pdf")
      assert_equal "Climate Change", out[:title]
      assert_equal Date.new(2024, 3, 15), out[:issued_date]
      assert_equal "Earth science research", out[:abstract]
      assert_equal [{ given: "John", family: "Doe" }, { given: "Jane", family: "Roe" }], out[:authors]
    end
  end

  test "lehnt 'Microsoft Word'-Junk-Title ab" do
    stub_info("Title" => "Microsoft Word - foo.doc", "Author" => "Hans") do
      assert_nil Inbox::Bib::EmbeddedInfo.call(path: "/tmp/x.pdf")
    end
  end

  test "lehnt zu kurzen Title ab" do
    stub_info("Title" => "X", "Author" => "Y") do
      assert_nil Inbox::Bib::EmbeddedInfo.call(path: "/tmp/x.pdf")
    end
  end

  test "split_authors für 'Doe, J.; Roe, J.'" do
    out = Inbox::Bib::EmbeddedInfo.split_authors("Doe, J.; Roe, J.")
    # Komma-Splits → einzelne Tokens als Family (Best-Effort bei Last-Comma-Style).
    assert_equal 4, out.size
  end
end
