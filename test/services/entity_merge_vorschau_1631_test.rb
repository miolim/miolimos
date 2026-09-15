require "test_helper"

# #1631 (aus immoOS #1608 übernommen). Hans dort: „Im Moment wird das
# Zusammenführen sofort durchgeführt. Vorher bitte eine Nachfrage einbauen, die
# die Konsequenzen aufzeigt und dann erst auf Bestätigung zusammenführt."
#
# immoOS prüft das an Konten und Zahlerregeln; im Kern stehen dafür eine
# Kontaktangabe und ein Thema, dessen Kunde die Quelle ist.
class EntityMergeVorschau1631Test < ActiveSupport::TestCase
  setup do
    @hans = create_human(password: "secretsecret")
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def verknuepfte_quelle
    source = FileProxy.create(actor: @hans, title: "Muster", item_type: :person, content: "",
                              topics: [], contacts: [], tags: [])
    target = FileProxy.create(actor: @hans, title: "Erika Muster", item_type: :person, content: "",
                              topics: [], contacts: [], tags: [])
    source.contact_points.create!(kind: "email", value: "muster-#{SecureRandom.hex(2)}@example.org")
    @thema = Topic.create!(name: "Kundenthema", slug: "kunde-#{SecureRandom.hex(3)}", creator: @hans,
                           customer_uuid: source.uuid)
    [source, target]
  end

  ohne_zaehler = ->(report) { report.except(:personally_known, :body_appended) }

  test "die Vorschau zählt, was der Merge umzieht — und schreibt nichts" do
    with_isolated_miolimos_base do
      source, target = verknuepfte_quelle
      adresse = source.contact_points.pluck(:value)

      vorschau = EntityMerge.vorschau(source: source, target: target)

      assert_operator vorschau.values.sum, :>=, 2, "Kontaktangabe und Thema: #{vorschau.inspect}"
      assert_equal 1, vorschau[:"topics.customer_uuid"]

      assert_not KnowledgeItem.with_discarded.find(source.uuid).discarded?, "die Quelle bleibt"
      assert_equal source.uuid, @thema.reload.customer_uuid
      assert_equal adresse, source.reload.contact_points.pluck(:value)

      bericht = EntityMerge.merge!(source: source.reload, target: target.reload, actor: @hans)
      assert_equal ohne_zaehler.call(vorschau), ohne_zaehler.call(bericht),
                   "die Nachfrage kündigt genau an, was der Merge dann tut"
    end
  end

  test "die Vorschau weist dieselben Fälle ab wie der Merge" do
    with_isolated_miolimos_base do
      source, = verknuepfte_quelle
      assert_raises(EntityMerge::Error) { EntityMerge.vorschau(source: source, target: source) }
    end
  end
end
