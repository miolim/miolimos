require "test_helper"

# #532 (Hans, 2026-06-08): Document-Datenmodell — Komposition + Beträge.
class DocumentTest < ActiveSupport::TestCase
  test "kind/status enums + prose?/invoice? Klassifizierung" do
    assert Document.new(kind: :brief).prose?
    assert Document.new(kind: :nda).prose?
    assert Document.new(kind: :rechnung).invoice?
    assert Document.new(kind: :angebot).invoice?
    refute Document.new(kind: :brief).invoice?
    assert_equal "entwurf", Document.new(kind: :brief).status
  end

  # #694 (Hans): gewählte Empfänger-Adresse nur, wenn sie zum Empfänger gehört.
  test "chosen_recipient_address respektiert nur Adressen des Empfängers" do
    mk = ->(t) { KnowledgeItem.create!(uuid: SecureRandom.uuid, title: t, item_type: :organization,
                                       file_path: "kb/#{SecureRandom.hex(4)}.md", content_hash: SecureRandom.hex(8)) }
    ki    = mk.call("Kasse")
    other = mk.call("Andere")
    a1 = PostalAddress.create!(knowledge_item_uuid: ki.uuid,    line1: "Postfach 1", city: "HH", kind: "post")
    a2 = PostalAddress.create!(knowledge_item_uuid: ki.uuid,    line1: "Hauptstr 1", city: "HH", kind: "post")
    fremd = PostalAddress.create!(knowledge_item_uuid: other.uuid, line1: "Fremd", city: "X", kind: "post")

    doc = Document.create!(kind: :brief, recipient_uuid: ki.uuid, recipient_address_id: a2.id)
    assert_equal a2.id, doc.chosen_recipient_address&.id

    doc.update!(recipient_address_id: fremd.id)   # fremde Adresse → ignoriert
    assert_nil doc.chosen_recipient_address

    doc.update!(recipient_address_id: nil)         # keine Wahl → automatisch
    assert_nil doc.chosen_recipient_address
    assert_equal a1, ki.mailing_address            # Default bleibt erste post-Adresse
  end

  test "salutation_line nutzt Override, sonst neutralen Default" do
    assert_equal "Sehr geehrte Damen und Herren", Document.new(kind: :brief).salutation_line
    assert_equal "Hallo Erika", Document.new(kind: :brief, salutation: "Hallo Erika").salutation_line
  end

  test "invoice_line berechnet Netto/Steuer/Brutto" do
    l = InvoiceLine.new(quantity: 12, unit_price: 120, tax_rate: 19)
    assert_equal 1440, l.net
    assert_in_delta 273.6, l.tax_amount, 0.001
    assert_in_delta 1713.6, l.gross, 0.001
  end

  test "Document summiert Beträge und liefert EN16931-Steueraufschlüsselung" do
    doc = Document.create!(kind: :rechnung)
    doc.invoice_lines.create!(description: "Beratung", quantity: 10, unit_price: 100, tax_rate: 19)
    doc.invoice_lines.create!(description: "Auslagen", quantity: 1, unit_price: 90,  tax_rate: 19)
    doc.invoice_lines.create!(description: "Buch",     quantity: 1, unit_price: 50,  tax_rate: 7)
    doc.reload

    assert_equal 1140, doc.net_total            # 1000 + 90 + 50
    # 19%: 1090 net -> 207.1 ; 7%: 50 net -> 3.5
    assert_in_delta 210.6, doc.tax_total, 0.001
    assert_in_delta 1350.6, doc.gross_total, 0.001

    bd = doc.tax_breakdown
    assert_equal [7, 19], bd.map { |g| g[:rate].to_i }
    g7  = bd.find { |g| g[:rate].to_i == 7 }
    g19 = bd.find { |g| g[:rate].to_i == 19 }
    assert_equal 50, g7[:net]
    assert_in_delta 3.5, g7[:tax], 0.001
    assert_equal 1090, g19[:net]
    assert_in_delta 207.1, g19[:tax], 0.001
  end

  test "referenziert Aussteller/Empfänger/Body als KIs ohne Doppelpflege" do
    hans = HumanActor.create!(name: "H", email: "d-#{SecureRandom.hex(3)}@t.local", password: "secretsecret")
    grant(hans, "KnowledgeItem", %w[read create update])
    iss  = FileProxy.create(actor: hans, title: "Firma GmbH", item_type: :organization, content: "")
    rec  = FileProxy.create(actor: hans, title: "Muster GmbH", item_type: :organization, content: "")
    body = FileProxy.create(actor: hans, title: "Brieftext", item_type: :note, content: "Sehr geehrte …")

    doc = Document.create!(kind: :brief, issuer_uuid: iss.uuid, recipient_uuid: rec.uuid, body_ki_uuid: body.uuid)
    assert_equal "Firma GmbH",  doc.issuer.title
    assert_equal "Muster GmbH", doc.recipient.title
    assert_equal "Brieftext",   doc.body_ki.title
  end
end
