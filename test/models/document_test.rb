require "test_helper"

# #532 (Hans, 2026-06-08) / #926: Document = das Anschreiben (Brief/NDA/
# SEPA-Mandat). Rechnung/Angebot sind zur Invoice-Entität ausgezogen.
class DocumentTest < ActiveSupport::TestCase
  test "kind/status enums der Anschreiben-Arten" do
    assert Document.new(kind: :brief).brief?
    assert Document.new(kind: :nda).nda?
    assert Document.new(kind: :lastschrift).lastschrift?
    assert_equal "entwurf", Document.new(kind: :brief).status
    # #926: rechnung/angebot sind KEINE Document-Kinds mehr.
    refute Document.kinds.key?("rechnung")
    refute Document.kinds.key?("angebot")
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

  # #926 Stufe 2: merge_context speist den {{key}}-Merge — gemeinsame
  # Schlüssel + Infoblock-Felder (Labels normalisiert).
  test "merge_context liefert Standard-Schlüssel + Infoblock-Felder" do
    doc = Document.create!(kind: :brief, subject: "Kündigung", document_date: Date.new(2026, 7, 1))
    doc.document_fields.create!(label: "Kaltmiete", value: "850 €", position: 0)
    ctx = doc.merge_context
    assert_equal "Kündigung", ctx["betreff"]
    assert_equal "850 €",     ctx["kaltmiete"]
    assert_equal "Sehr geehrte Damen und Herren", ctx["anrede"]
    assert ctx.key?("datum")
  end
end
