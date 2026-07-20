require "test_helper"

# #1073 (Hans, 2026-07-20): Adressen haben Gueltigkeitszeitraeume. Der
# Anlass: zieht ein Mieter in das verwaltete Objekt, soll die vorherige
# Postanschrift erhalten bleiben — aber Briefe duerfen nie mehr dorthin
# adressiert werden. Genau diese Trennung (Historie behalten, Auswahl
# einschraenken) sichern die Tests hier ab.
class PostalAddressValidityTest < ActiveSupport::TestCase
  setup do
    @person = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Mieter",
                                    item_type: :person,
                                    file_path: "kb/#{SecureRandom.hex(4)}.md",
                                    content_hash: SecureRandom.hex(8))
  end

  def addr(**attrs)
    PostalAddress.create!(knowledge_item_uuid: @person.uuid,
                          line1: "Adresse-#{SecureRandom.hex(2)}", city: "HH", **attrs)
  end

  test "ohne Zeitraum gilt eine Adresse unbefristet" do
    a = addr
    assert_predicate a, :current?
    refute_predicate a, :former?
    refute_predicate a, :future?
    assert_nil a.validity_label, "unbefristet braucht kein Label"
  end

  test "current?/former?/future? am Stichtag" do
    alt = addr(valid_until: Date.new(2026, 5, 31))
    neu = addr(valid_from: Date.new(2026, 6, 1))

    assert alt.current?(Date.new(2026, 5, 31)),  "Ende ist einschliesslich"
    assert alt.former?(Date.new(2026, 6, 1))
    assert neu.current?(Date.new(2026, 6, 1)),   "Beginn ist einschliesslich"
    assert neu.future?(Date.new(2026, 5, 31))
  end

  test "Scopes current/former filtern am Stichtag" do
    alt = addr(valid_until: Date.new(2026, 5, 31))
    neu = addr(valid_from: Date.new(2026, 6, 1))
    dauerhaft = addr

    on = Date.new(2026, 7, 1)
    assert_equal [neu.id, dauerhaft.id].sort, PostalAddress.current(on).pluck(:id).sort
    assert_equal [alt.id], PostalAddress.former(on).pluck(:id)
  end

  test "valid_until vor valid_from ist ungueltig" do
    a = PostalAddress.new(knowledge_item_uuid: @person.uuid, line1: "X", city: "HH",
                          valid_from: Date.new(2026, 6, 1), valid_until: Date.new(2026, 5, 1))
    refute_predicate a, :valid?
    assert a.errors.of_kind?(:valid_until, :invalid) || a.errors[:valid_until].any?
  end

  test "validity_label formuliert offene und geschlossene Zeitraeume" do
    assert_equal "bis 31.05.2026",             addr(valid_until: Date.new(2026, 5, 31)).validity_label
    assert_equal "seit 01.06.2026",            addr(valid_from: Date.new(2026, 6, 1)).validity_label
    assert_equal "01.01.2020 – 31.05.2026",
                 addr(valid_from: Date.new(2020, 1, 1), valid_until: Date.new(2026, 5, 31)).validity_label
  end

  # ─── Auswahl fuer Briefe ──────────────────────────────────────────

  test "mailing_address nimmt die aktuelle, nicht die abgelaufene Anschrift" do
    alt = addr(kind: "post", valid_until: Date.new(2026, 5, 31))
    neu = addr(kind: "post", valid_from: Date.new(2026, 6, 1))

    assert_equal neu, @person.reload.mailing_address(Date.new(2026, 7, 1))
    # Rueckblick: zum damaligen Stichtag war die alte richtig.
    assert_equal alt, @person.reload.mailing_address(Date.new(2026, 4, 1))
  end

  test "primary_address bevorzugt billing nur unter den gueltigen" do
    abgelaufen_billing = addr(billing: true, valid_until: Date.new(2026, 5, 31))
    aktuell            = addr(valid_from: Date.new(2026, 6, 1))

    assert_equal aktuell, @person.reload.primary_address(Date.new(2026, 7, 1)),
                 "eine abgelaufene Rechnungsadresse darf nicht gewinnen"
    assert_equal abgelaufen_billing, @person.reload.primary_address(Date.new(2026, 4, 1))
  end

  # Fallback: lieber eine veraltete Anschrift als ein leeres Adressfeld.
  # Bestandsdaten ohne Zeitraum sind ohnehin unbefristet, dieser Fall
  # entsteht nur, wenn ALLE Adressen befristet und abgelaufen sind.
  test "sind alle Adressen abgelaufen, bleibt die Auswahl trotzdem befuellt" do
    alt = addr(valid_until: Date.new(2026, 5, 31))

    assert_equal alt, @person.reload.primary_address(Date.new(2026, 7, 1))
    assert_equal [alt], @person.reload.current_addresses(Date.new(2026, 7, 1))
  end

  test "Bestandsadressen ohne Zeitraum bleiben unveraendert waehlbar" do
    a = addr(kind: "post")
    assert_equal a, @person.reload.mailing_address
    assert_equal a, @person.reload.primary_address
  end
end
