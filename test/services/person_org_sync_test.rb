require "test_helper"

class PersonOrgSyncTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
  end

  # ─── Affiliations ────────────────────────────────────────────────────────

  test "sync_affiliations creates rows from frontmatter (UUID-Ref)" do
    with_isolated_miolimos_base do
      org    = FileProxy.create(actor: @hans, title: "BigCorp",
                                item_type: :organization, content: "")
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")

      fm = {
        "affiliations" => [
          { "org" => org.uuid, "role" => "Founder", "from" => "2020-01-01", "primary" => true }
        ]
      }
      PersonOrgSync.sync(person, fm)

      affs = person.affiliations_as_person.to_a
      assert_equal 1, affs.size
      a = affs.first
      assert_equal org.uuid, a.organization_uuid
      assert_equal "Founder", a.role
      assert_equal Date.parse("2020-01-01"), a.start_at
      assert_nil a.end_at
      assert_equal true, a.primary
    end
  end

  test "sync_affiliations resolves Title-Ref to UUID (case-insensitive)" do
    with_isolated_miolimos_base do
      org = FileProxy.create(actor: @hans, title: "BigCorp",
                             item_type: :organization, content: "")
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")

      fm = { "affiliations" => [{ "org" => "bigcorp", "role" => "Engineer" }] }
      PersonOrgSync.sync(person, fm)

      assert_equal org.uuid, person.affiliations_as_person.first.organization_uuid
    end
  end

  test "sync_affiliations accepts year-only `from`" do
    with_isolated_miolimos_base do
      org    = FileProxy.create(actor: @hans, title: "BigCorp",
                                item_type: :organization, content: "")
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")

      PersonOrgSync.sync(person, { "affiliations" => [{ "org" => org.uuid, "from" => "2018" }] })
      assert_equal Date.new(2018, 1, 1), person.affiliations_as_person.first.start_at
    end
  end

  test "sync_affiliations is idempotent on re-sync" do
    with_isolated_miolimos_base do
      org    = FileProxy.create(actor: @hans, title: "BigCorp",
                                item_type: :organization, content: "")
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")

      fm = { "affiliations" => [{ "org" => org.uuid, "role" => "Founder", "from" => "2020-01-01" }] }
      PersonOrgSync.sync(person, fm)
      PersonOrgSync.sync(person, fm)
      PersonOrgSync.sync(person, fm)

      assert_equal 1, person.affiliations_as_person.count
    end
  end

  test "sync_affiliations removes entries that disappear from frontmatter" do
    with_isolated_miolimos_base do
      org_a  = FileProxy.create(actor: @hans, title: "OrgA",
                                item_type: :organization, content: "")
      org_b  = FileProxy.create(actor: @hans, title: "OrgB",
                                item_type: :organization, content: "")
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")

      PersonOrgSync.sync(person, { "affiliations" => [
        { "org" => org_a.uuid, "role" => "X" },
        { "org" => org_b.uuid, "role" => "Y" }
      ]})
      assert_equal 2, person.affiliations_as_person.count

      PersonOrgSync.sync(person, { "affiliations" => [{ "org" => org_a.uuid, "role" => "X" }] })
      assert_equal 1, person.affiliations_as_person.count
      assert_equal org_a.uuid, person.affiliations_as_person.first.organization_uuid
    end
  end

  test "sync_affiliations skips entries with unresolvable `org`" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")
      PersonOrgSync.sync(person, { "affiliations" => [
        { "org" => "Nicht-Existent-Inc", "role" => "Stranger" }
      ]})
      assert_equal 0, person.affiliations_as_person.count
    end
  end

  test "sync_affiliations only runs on persons (not on organizations)" do
    with_isolated_miolimos_base do
      org_a = FileProxy.create(actor: @hans, title: "OrgA",
                               item_type: :organization, content: "")
      org_b = FileProxy.create(actor: @hans, title: "OrgB",
                               item_type: :organization, content: "")

      # Wenn jemand auf einer Org-Seite affiliations: einträgt, ignorieren wir
      # das — Affiliations sind ein Person-Konzept.
      PersonOrgSync.sync(org_a, { "affiliations" => [{ "org" => org_b.uuid, "role" => "Tochter" }] })
      assert_equal 0, Affiliation.where(person_uuid: org_a.uuid).count
    end
  end

  # ─── Relationships ───────────────────────────────────────────────────────

  test "sync_relationships creates rows from frontmatter" do
    with_isolated_miolimos_base do
      a = FileProxy.create(actor: @hans, title: "Alice",
                           item_type: :person, content: "")
      b = FileProxy.create(actor: @hans, title: "Bob",
                           item_type: :person, content: "")

      PersonOrgSync.sync(a, { "relationships" => [
        { "to" => b.uuid, "kind" => "Ehepartner", "since" => "2010" }
      ]})

      rels = a.outgoing_relationships.to_a
      assert_equal 1, rels.size
      r = rels.first
      assert_equal b.uuid, r.to_uuid
      assert_equal "Ehepartner", r.kind
      assert_equal Date.new(2010, 1, 1), r.start_at
    end
  end

  test "sync_relationships resolves Title-Ref" do
    with_isolated_miolimos_base do
      a = FileProxy.create(actor: @hans, title: "Alice",
                           item_type: :person, content: "")
      b = FileProxy.create(actor: @hans, title: "Bob",
                           item_type: :person, content: "")

      PersonOrgSync.sync(a, { "relationships" => [{ "to" => "bob", "kind" => "Freund" }] })
      assert_equal b.uuid, a.outgoing_relationships.first.to_uuid
    end
  end

  test "sync_relationships skips entries without kind" do
    with_isolated_miolimos_base do
      a = FileProxy.create(actor: @hans, title: "Alice",
                           item_type: :person, content: "")
      b = FileProxy.create(actor: @hans, title: "Bob",
                           item_type: :person, content: "")

      PersonOrgSync.sync(a, { "relationships" => [{ "to" => b.uuid, "kind" => "" }] })
      assert_equal 0, a.outgoing_relationships.count
    end
  end

  test "sync_relationships removes entries that disappear" do
    with_isolated_miolimos_base do
      a = FileProxy.create(actor: @hans, title: "Alice",
                           item_type: :person, content: "")
      b = FileProxy.create(actor: @hans, title: "Bob",
                           item_type: :person, content: "")
      c = FileProxy.create(actor: @hans, title: "Carol",
                           item_type: :person, content: "")

      PersonOrgSync.sync(a, { "relationships" => [
        { "to" => b.uuid, "kind" => "Freund" },
        { "to" => c.uuid, "kind" => "Kollegin" }
      ]})
      assert_equal 2, a.outgoing_relationships.count

      PersonOrgSync.sync(a, { "relationships" => [{ "to" => b.uuid, "kind" => "Freund" }] })
      assert_equal 1, a.outgoing_relationships.count
      assert_equal b.uuid, a.outgoing_relationships.first.to_uuid
    end
  end

  test "sync runs on organizations too (relationships, but not affiliations)" do
    with_isolated_miolimos_base do
      parent = FileProxy.create(actor: @hans, title: "BigCorp",
                                item_type: :organization, content: "")
      child  = FileProxy.create(actor: @hans, title: "BigCorp Engineering",
                                item_type: :organization, content: "")

      PersonOrgSync.sync(child, { "relationships" => [
        { "to" => parent.uuid, "kind" => "parent_org" }
      ]})
      assert_equal 1, child.outgoing_relationships.count
    end
  end

  # ─── Edge cases ──────────────────────────────────────────────────────────

  test "sync handles missing/empty frontmatter gracefully" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")
      assert_nothing_raised { PersonOrgSync.sync(person, nil) }
      assert_nothing_raised { PersonOrgSync.sync(person, {}) }
      assert_nothing_raised { PersonOrgSync.sync(person, { "affiliations" => [] }) }
    end
  end
end
