require "test_helper"

class Inbox::Bib::IsbnOpenlibraryTest < ActiveSupport::TestCase
  test "valid_isbn13 erkennt korrekte Prüfziffer" do
    assert Inbox::Bib::IsbnOpenlibrary.valid_isbn13?("9780306406157")
    refute Inbox::Bib::IsbnOpenlibrary.valid_isbn13?("9780306406158")
  end

  test "valid_isbn10 erkennt korrekte Prüfziffer (auch mit X)" do
    assert Inbox::Bib::IsbnOpenlibrary.valid_isbn10?("0306406152")
    assert Inbox::Bib::IsbnOpenlibrary.valid_isbn10?("097522980X")
    refute Inbox::Bib::IsbnOpenlibrary.valid_isbn10?("0306406151")
  end

  test "find_valid_isbn extrahiert aus Freitext mit Trennern" do
    text = "Impressum\nISBN: 978-0-306-40615-7\nAuflage 2024"
    assert_equal "9780306406157", Inbox::Bib::IsbnOpenlibrary.find_valid_isbn(text)
  end

  test "find_valid_isbn lässt Telefonnummern fallen" do
    text = "Hotline +49 30 12345 67890 anrufen"
    assert_nil Inbox::Bib::IsbnOpenlibrary.find_valid_isbn(text)
  end

  test "normalize aus OpenLibrary-Antwort" do
    ol = {
      "title" => "Climate Change",
      "subtitle" => "A Primer",
      "authors" => [{ "name" => "John Doe" }, { "name" => "Jane Q. Roe" }],
      "publishers" => [{ "name" => "Acme" }],
      "publish_places" => [{ "name" => "Berlin" }],
      "publish_date" => "2024",
      "number_of_pages" => 350,
      "url" => "https://openlibrary.org/works/OL123W"
    }
    out = Inbox::Bib::IsbnOpenlibrary.normalize(ol, isbn: "9780306406157")
    assert_equal "book", out[:csl_type]
    assert_equal "Climate Change: A Primer", out[:title]
    assert_equal "Acme", out[:publisher]
    assert_equal "Berlin", out[:publisher_place]
    assert_equal Date.new(2024, 1, 1), out[:issued_date]
    assert_equal "350", out[:pages]
    assert_equal "ISBN", out[:identifier][:scheme]
    assert_equal [{ given: "John", family: "Doe" }, { given: "Jane Q.", family: "Roe" }], out[:authors]
  end
end
