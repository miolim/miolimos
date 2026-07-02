require "test_helper"

# #378 (Hans, 2026-05-26): Tests fuer PersonKiResolver — Lookup +
# Auto-Create von Person/Org-KIs aus „Contact Slug\" oder E-Mail-Form.
class PersonKiResolverTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  test "find returns nil when slug is blank" do
    assert_nil PersonKiResolver.find("")
    assert_nil PersonKiResolver.find(nil)
  end

  test "find returns existing person KI by parameterized title" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Max Mustermann",
                            item_type: :person, content: "x")
      assert_equal ki.uuid, PersonKiResolver.find("max-mustermann")&.uuid
    end
  end

  test "find returns existing organization KI" do
    with_isolated_miolimos_base do
      org = FileProxy.create(actor: @hans, title: "Anthropic",
                             item_type: :organization, content: "y")
      assert_equal org.uuid, PersonKiResolver.find("anthropic")&.uuid
    end
  end

  test "find returns nil for unknown slug" do
    with_isolated_miolimos_base do
      assert_nil PersonKiResolver.find("does-not-exist")
    end
  end

  test "find_or_create! returns existing person without duplicating" do
    with_isolated_miolimos_base do
      existing = FileProxy.create(actor: @hans, title: "Anna Bauer",
                                  item_type: :person, content: "")
      result = PersonKiResolver.find_or_create!("anna-bauer", actor: @hans)
      assert_equal existing.uuid, result.uuid
    end
  end

  test "find_or_create! with hyphenated slug creates Person-KI" do
    with_isolated_miolimos_base do
      result = PersonKiResolver.find_or_create!("john-doe", actor: @hans)
      assert_equal "person", result.item_type
      assert_equal "John Doe", result.title
      assert_equal "John", result.first_name
      assert_equal "Doe",  result.last_name
    end
  end

  test "find_or_create! with single-word slug creates Organization-KI" do
    with_isolated_miolimos_base do
      result = PersonKiResolver.find_or_create!("acme", actor: @hans)
      assert_equal "organization", result.item_type
      assert_equal "Acme", result.title
    end
  end

  test "find_or_create! returns nil for empty slug" do
    with_isolated_miolimos_base do
      assert_nil PersonKiResolver.find_or_create!("", actor: @hans)
    end
  end

  test "find_or_create_by_email! creates Person + ContactPoint" do
    with_isolated_miolimos_base do
      result = PersonKiResolver.find_or_create_by_email!("jane.doe@example.com",
                                                          actor: @hans)
      assert_equal "person", result.item_type
      assert_equal "Jane Doe", result.title
      cps = ContactPoint.where(knowledge_item_uuid: result.uuid)
      assert cps.exists?(kind: "email", value: "jane.doe@example.com")
    end
  end

  test "find_or_create_by_email! reuses Person when email already has a ContactPoint" do
    with_isolated_miolimos_base do
      first  = PersonKiResolver.find_or_create_by_email!("user@x.org", actor: @hans)
      second = PersonKiResolver.find_or_create_by_email!("user@x.org", actor: @hans)
      assert_equal first.uuid, second.uuid
    end
  end

  test "find_or_create_by_email! ignores blank email" do
    with_isolated_miolimos_base do
      assert_nil PersonKiResolver.find_or_create_by_email!("", actor: @hans)
    end
  end

  # #764 (Hans, 2026-06-23): Ein VERWORFENER Kontakt mit derselben E-Mail darf
  # den Lookup nicht kapern — sonst wurde trotz lebendem Kontakt ein Duplikat
  # angelegt (verwaister ContactPoint des verworfenen KIs → find_by(nil)).
  test "find_or_create_by_email! findet den LEBENDEN Kontakt trotz verworfenem Duplikat mit gleicher E-Mail" do
    with_isolated_miolimos_base do
      # Verworfenes Duplikat zuerst (kleinere id → früher im Lookup).
      dup = PersonKiResolver.find_or_create_by_email!("kontakt@firma.de", actor: @hans)
      live = FileProxy.create(actor: @hans, title: "Echter Kontakt", item_type: :person, content: "")
      FileProxy.update(actor: @hans, knowledge_item: live,
                       contact_points: [{ "kind" => "email", "value" => "kontakt@firma.de" }])
      FileProxy.destroy(actor: @hans, knowledge_item: dup)   # discard

      found = PersonKiResolver.find_or_create_by_email!("kontakt@firma.de", actor: @hans)
      assert_equal live.uuid, found.uuid, "muss den lebenden Kontakt finden, nicht neu anlegen"
      assert_equal 1, KnowledgeItem.persons_and_orgs.where("title = ?", "Echter Kontakt").count
    end
  end
end
