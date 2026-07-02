require "test_helper"

# #801 P2: Tests für die aus dem KnowledgeItemsController extrahierte
# Kontaktdaten-Übernahme (#761). Grundregel: nur LEERE Felder füllen,
# bestehende Werte nie überschreiben.
class ContactEnrichmentTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
  end

  def create_person(**attrs)
    FileProxy.create(actor: @hans, title: "P-#{SecureRandom.hex(3)}",
                     item_type: :person, content: "x").tap { |p| p.update!(**attrs) if attrs.any? }
  end

  test "apply fills empty contact points and reports German labels" do
    with_isolated_miolimos_base do
      person = create_person
      added = ContactEnrichment.new(item: person, actor: @hans)
                               .apply({ email: "a@b.de", phone: "0123-456" })
      assert_equal ["E-Mail", "Telefon"], added
      person.reload
      assert_equal %w[email phone], person.contact_points.map(&:kind).sort
    end
  end

  test "apply never overwrites existing contact points (case-insensitive match)" do
    with_isolated_miolimos_base do
      person = create_person
      ContactEnrichment.new(item: person, actor: @hans).apply({ email: "A@B.de" })
      added = ContactEnrichment.new(item: person.reload, actor: @hans)
                               .apply({ email: "a@b.DE", phone: "0123" })
      assert_equal ["Telefon"], added
      assert_equal 1, person.reload.contact_points.where(kind: "email").count
    end
  end

  test "apply derives the site URL from the source URL when the page names none" do
    with_isolated_miolimos_base do
      person = create_person
      added = ContactEnrichment.new(item: person, actor: @hans)
                               .apply({}, source_url: "https://firma.example/impressum")
      assert_equal ["Web"], added
      assert_equal "https://firma.example",
                   person.reload.contact_points.find_by(kind: "url").value
    end
  end

  test "apply adds identifiers unless label or value already exists" do
    with_isolated_miolimos_base do
      person = create_person
      person.identifiers.create!(label: "USt-IdNr", value: "DE111", position: 0)

      added = ContactEnrichment.new(item: person, actor: @hans)
                               .apply({ vat_id: "DE999", register: "HRB 123" })
      assert_equal ["Handelsregister"], added
      assert_equal "DE111", person.reload.identifiers.find_by(label: "USt-IdNr").value
      assert person.identifiers.exists?(label: "Handelsregister", value: "HRB 123")
    end
  end

  test "apply adds postal address only when none exists" do
    with_isolated_miolimos_base do
      person = create_person
      addr = { line1: "Weg 1", postal_code: "12345", city: "Ort", country: "DE" }
      enrich = ContactEnrichment.new(item: person, actor: @hans)

      assert_includes enrich.apply({ address: addr }), I18n.t("knowledge.detail.complete_address_field")
      assert_equal 1, person.reload.postal_addresses.count

      # zweiter Lauf: Adresse existiert → nichts hinzugefügt
      assert_equal [], ContactEnrichment.new(item: person, actor: @hans).apply({ address: addr })
      assert_equal 1, person.reload.postal_addresses.count
    end
  end

  test "apply links parent org by title when the org KI exists" do
    with_isolated_miolimos_base do
      org    = FileProxy.create(actor: @hans, title: "ACME GmbH",
                                item_type: :organization, content: "x")
      person = create_person
      added = ContactEnrichment.new(item: person, actor: @hans)
                               .apply({ organization: "ACME GmbH" })
      assert_includes added, I18n.t("knowledge.detail.complete_org_field")
      assert_equal org.uuid, person.reload.parent_org_uuid
    end
  end

  test "apply leaves an existing parent org untouched" do
    with_isolated_miolimos_base do
      org    = FileProxy.create(actor: @hans, title: "Bestand GmbH",
                                item_type: :organization, content: "x")
      person = create_person(parent_org_uuid: org.uuid)
      added  = ContactEnrichment.new(item: person, actor: @hans)
                                .apply({ organization: "Andere GmbH" })
      assert_not_includes added, I18n.t("knowledge.detail.complete_org_field")
      assert_equal org.uuid, person.reload.parent_org_uuid
    end
  end

  test "from_url extracts and applies in one call" do
    with_isolated_miolimos_base do
      person = create_person
      original = ContactExtractor.method(:call)
      ContactExtractor.define_singleton_method(:call) { |_url| { email: "info@acme.de" } }
      begin
        added = ContactEnrichment.from_url(item: person, actor: @hans,
                                           url: "https://acme.de/impressum")
        assert_includes added, "E-Mail"
        # Web-Kontaktpunkt aus der Quell-Domain abgeleitet
        assert_includes added, "Web"
      ensure
        ContactExtractor.singleton_class.send(:remove_method, :call)
        ContactExtractor.define_singleton_method(:call, original)
      end
    end
  end
end
