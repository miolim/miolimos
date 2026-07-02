require "test_helper"

class TopicSlugResolverTest < ActiveSupport::TestCase
  test "returns existing topic when slug already known" do
    creator = create_human
    existing = create_topic(creator: creator, slug: "known-slug")
    resolved = Topic.find_or_create_from_slug!("known-slug", creator: create_human)
    assert_equal existing, resolved
  end

  test "creates active non-template topic when slug is unknown" do
    creator = create_human
    t = Topic.find_or_create_from_slug!("brand-new-thing", creator: creator)
    assert t.persisted?
    assert_equal "Brand New Thing", t.name
    assert t.active?
    refute t.template?
    assert_equal creator, t.creator
  end

  test "is idempotent on repeated calls" do
    creator = create_human
    a = Topic.find_or_create_from_slug!("idem-slug", creator: creator)
    b = Topic.find_or_create_from_slug!("idem-slug", creator: create_human)
    assert_equal a, b
    assert_equal 1, Topic.where(slug: "idem-slug").count
  end
end

class PersonKiResolverTest < ActiveSupport::TestCase
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-#{SecureRandom.hex(4)}@t.local", active: true)
    Capability.create!(actor: @hans, resource_type: "KnowledgeItem",
                       actions: %w[read create update delete], effect: :allow)

    @tmp_base = Dir.mktmpdir("miolimos-resolver-")
    @prev_base = FileProxy.const_get(:BASE_PATH)
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, Pathname.new(@tmp_base))
    Dir.chdir(@tmp_base) do
      system("git", "init", "-q", "-b", "main")
      system("git", "-c", "user.name=test", "-c", "user.email=test@test.local",
             "commit", "--allow-empty", "-q", "-m", "root")
    end
  end

  teardown do
    FileProxy.send(:remove_const, :BASE_PATH)
    FileProxy.const_set(:BASE_PATH, @prev_base)
    FileUtils.remove_entry(@tmp_base) if @tmp_base && File.exist?(@tmp_base)
  end

  test "returns existing person KI when slug already maps to a title" do
    existing = FileProxy.create(
      actor: @hans, title: "Jane Doe Known", item_type: :person,
      content: "", topics: [], contacts: [], tags: []
    )
    assert_equal existing, PersonKiResolver.find_or_create!("jane-doe-known", actor: @hans)
  end

  test "hyphenated slug creates a Person-KI (first-last heuristic)" do
    c = PersonKiResolver.find_or_create!("thomas-lederer", actor: @hans)
    assert c.person?
    assert_equal "Thomas", c.first_name
    assert_equal "Lederer", c.last_name
  end

  test "single-token slug creates an Organization-KI" do
    c = PersonKiResolver.find_or_create!("anthropic", actor: @hans)
    assert c.organization?
    assert_equal "Anthropic", c.title
  end

  test "is idempotent" do
    a = PersonKiResolver.find_or_create!("idem-contact", actor: @hans)
    b = PersonKiResolver.find_or_create!("idem-contact", actor: @hans)
    assert_equal a, b
    assert_equal 1, KnowledgeItem.persons_and_orgs.where("title ILIKE ?", "Idem Contact").count
  end
end
