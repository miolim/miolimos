require "test_helper"

class AuthorshipTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  test "attach_by_name creates a provisional person stub and links it as author" do
    with_isolated_miolimos_base do
      src = Source.create!(title: "Studie", csl_type: "article-journal", issued_string: "2024", creator: @hans)
      sc  = Authorship.attach_by_name(source: src, name: "Max Müller", actor: @hans)

      assert sc.persisted?
      assert sc.provisional?, "link should default to provisional"
      person = sc.knowledge_item
      assert_equal "person", person.item_type
      assert_equal "Müller", person.last_name
      assert_equal "Max", person.first_name
      assert_includes person.tags.to_a, Authorship::STUB_TAG
      # citekey nutzt jetzt den Autor-Nachnamen
      src.reload
      assert_match(/Müller/, src.display_authors)
      assert_match(/\Amuller_2024_\d+\z/, src.build_citation_slug)
    end
  end

  test "attach_by_name reuses an existing person (no duplicate stub)" do
    with_isolated_miolimos_base do
      s1 = Source.create!(title: "A", csl_type: "book", creator: @hans)
      s2 = Source.create!(title: "B", csl_type: "book", creator: @hans)
      Authorship.attach_by_name(source: s1, name: "Max Müller", actor: @hans)
      assert_no_difference -> { KnowledgeItem.where(item_type: "person").count } do
        Authorship.attach_by_name(source: s2, name: "Max Müller", actor: @hans)
      end
    end
  end

  test "split_name handles common Western European forms" do
    assert_equal ["Müller", "Max"],            Authorship.split_name("Max Müller")
    assert_equal ["Müller", "Max"],            Authorship.split_name("Müller, Max")
    assert_equal ["Schmidt", "Anna Maria"],    Authorship.split_name("Anna Maria Schmidt")
    assert_equal ["von der Heide", "Max"],     Authorship.split_name("Max von der Heide")
    assert_equal ["van Beethoven", "Ludwig"],  Authorship.split_name("Ludwig van Beethoven")
    assert_equal ["Bismarck", "Otto"],         Authorship.split_name("Otto Bismarck")
    assert_equal ["Cher", nil],                Authorship.split_name("Cher")
  end

  test "identify! marks the link confirmed with confidence + grounds" do
    with_isolated_miolimos_base do
      src = Source.create!(title: "C", csl_type: "book", creator: @hans)
      sc  = Authorship.attach_by_name(source: src, name: "Anna Schmidt", actor: @hans)
      sc.identify!(confidence: "bestätigt", via: "orcid", by: @hans)
      assert sc.reload.identified?
      assert_equal "bestätigt", sc.confidence
      assert_equal "orcid", sc.identified_via
      assert_equal @hans.id, sc.identified_by_id
    end
  end
end
