require "test_helper"

class KnowledgeItemUpdateFormTest < ActiveSupport::TestCase
  def args(params)
    KnowledgeItemUpdateForm.new(params).to_update_args
  end

  test "passes scalar fields through, omits absent ones" do
    out = args(title: "T", item_type: "note")
    assert_equal "T",     out[:title]
    assert_equal "note",  out[:item_type]
    refute_includes out.keys, :content
    refute_includes out.keys, :source
  end

  test "splits slug-list strings on whitespace and commas" do
    out = args(topics: "alpha, beta gamma", contacts: "x")
    assert_equal %w[alpha beta gamma], out[:topics]
    assert_equal %w[x],                out[:contacts]
  end

  test "passes slug-list arrays through, dropping blanks" do
    out = args(tags: ["a", "", " ", "b"])
    assert_equal %w[a b], out[:tags]
  end

  test "aliases: comma split for strings, blank-strip for arrays" do
    assert_equal %w[a b],   args(aliases: "a, b")[:aliases]
    assert_equal %w[a b c], args(aliases: ["a", "", "b", "c"])[:aliases]
  end

  test "affiliations drop rows without org and stringify keys with stripped values" do
    out = args(affiliations: [
      { "org" => "  Acme  ", "role" => " CEO ", "from" => "2024-01-01", "primary" => "1" },
      { "org" => "" }, # filter
      { "org" => "Beta", "primary" => false }
    ])
    assert_equal 2, out[:affiliations].size
    assert_equal "Acme", out[:affiliations][0]["org"]
    assert_equal "CEO",  out[:affiliations][0]["role"]
    assert_equal true,   out[:affiliations][0]["primary"]
    assert_equal "Beta", out[:affiliations][1]["org"]
    assert_equal false,  out[:affiliations][1]["primary"]
  end

  test "relationships drop rows missing to or kind" do
    out = args(relationships: [
      { "to" => "u-1", "kind" => "spouse" },
      { "to" => "",    "kind" => "friend" }, # filter
      { "to" => "u-2", "kind" => ""       }  # filter
    ])
    assert_equal 1, out[:relationships].size
    assert_equal "u-1",    out[:relationships][0]["to"]
    assert_equal "spouse", out[:relationships][0]["kind"]
  end

  test "contact_points default kind to email and drop empty values" do
    out = args(contact_points: [
      { "label" => "Privat", "value" => " hi@example.com " },
      { "kind"  => "phone",  "value" => "0123" },
      { "value" => "" } # filter
    ])
    assert_equal 2, out[:contact_points].size
    assert_equal "email",          out[:contact_points][0]["kind"]
    assert_equal "hi@example.com", out[:contact_points][0]["value"]
    assert_equal "phone",          out[:contact_points][1]["kind"]
  end

  test "absent params produce no key in output (FileProxy.update will leave the field unchanged)" do
    out = args({})
    assert_equal({}, out)
  end

  test "explicit nil for slug fields yields nil (signal: clear-list)" do
    out = args(topics: nil)
    assert_includes out.keys, :topics
    assert_nil out[:topics]
  end

  test "ActionController::Parameters work via permit-fallback" do
    permitted_array = [
      ActionController::Parameters.new(org: "X", role: "Lead", primary: "1")
    ]
    out = args(affiliations: permitted_array)
    assert_equal "X", out[:affiliations][0]["org"]
    assert_equal true, out[:affiliations][0]["primary"]
  end
end
