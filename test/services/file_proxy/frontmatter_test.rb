require "test_helper"
require "ostruct"

class FileProxy::FrontmatterTest < ActiveSupport::TestCase
  setup do
    @ki = OpenStruct.new(uuid: "fixed-uuid-1")
  end

  def build(old_fm, **overrides)
    defaults = { new_type: "note", topics: nil, contacts: nil, tags: nil,
                 aliases: nil, parent_org: nil, affiliations: nil,
                 relationships: nil, contact_points: nil,
                 first_name: nil, last_name: nil }
    FileProxy::Frontmatter.build(old_fm, @ki, **defaults.merge(overrides))
  end

  test "build refreshes updated_at and sets type from new_type" do
    fm = build({}, new_type: "abstract")
    assert_equal "abstract", fm["type"]
    assert_not_nil fm["updated_at"]
  end

  test "build keeps existing id, fills missing id from KI uuid" do
    assert_equal "existing-id-9", build({ "id" => "existing-id-9" })["id"]
    assert_equal @ki.uuid,        build({})["id"]
  end

  test "build replaces topics/contacts/tags arrays only when supplied" do
    old = { "topics" => ["a"], "contacts" => ["b"], "tags" => ["c"] }
    kept = build(old)
    assert_equal ["a"], kept["topics"]
    assert_equal ["b"], kept["contacts"]
    assert_equal ["c"], kept["tags"]

    replaced = build(old, topics: ["x"], contacts: ["y"], tags: ["z"])
    assert_equal ["x"], replaced["topics"]
    assert_equal ["y"], replaced["contacts"]
    assert_equal ["z"], replaced["tags"]
  end

  test "build drops blank aliases and omits the key when none remain" do
    fm = build({}, aliases: ["", "Alt"])
    assert_equal ["Alt"], fm["aliases"]

    fm2 = build({}, aliases: ["", nil])
    assert_nil fm2["aliases"]
  end

  test "build strips legacy keys source / source_url / chat_title" do
    fm = build({ "source" => "x", "source_url" => "u", "chat_title" => "t" })
    refute fm.key?("source")
    refute fm.key?("source_url")
    refute fm.key?("chat_title")
  end

  test "build leaves optional contact fields unchanged when keyword is nil" do
    old = { "parent_org" => "org-uuid", "first_name" => "Hans" }
    fm = build(old)
    assert_equal "org-uuid", fm["parent_org"]
    assert_equal "Hans",     fm["first_name"]
  end

  test "build writes optional contact fields when keyword is given" do
    fm = build({}, parent_org: "neue-org", first_name: "Erika", last_name: "Mustermann")
    assert_equal "neue-org",    fm["parent_org"]
    assert_equal "Erika",       fm["first_name"]
    assert_equal "Mustermann",  fm["last_name"]
  end

  test "render emits frontmatter delimiters, H1 title and body" do
    out = FileProxy::Frontmatter.render(
      fm: { "id" => "1", "type" => "note" },
      title: "Hello",
      body:  "world\n"
    )
    assert out.start_with?("---\n")
    assert_match %r{^---\n.*?\n---\n\n# Hello\n\nworld\n}m, out
  end
end
