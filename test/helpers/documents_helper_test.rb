require "test_helper"

# #1171 (aus immoOS #1157 E4 + #1170): GiroCode auf dem Anschreiben — Betrag
# aus dem Infoblock-Feld „Zahlbetrag", von Hand editierbar, also muss das
# Parsing beide Dezimalformate verstehen („1234.56" wäre naiv 123.456 €).
# Dazu #1069: mehrzeiliges Anschriftfeld mit optionaler Kurzform.
class DocumentsHelperTest < ActionView::TestCase
  setup do
    @iss = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "HV GmbH",
                                 item_type: :organization,
                                 file_path: "kb/#{SecureRandom.hex(4)}.md",
                                 content_hash: SecureRandom.hex(8))
    @iss.bank_accounts.create!(iban: "DE89370400440532013000", position: 0)
  end

  def brief_with_zahlbetrag(value)
    doc = Document.create!(kind: :brief, issuer_uuid: @iss.uuid)
    doc.document_fields.create!(label: "Zahlbetrag", value: value)
    doc
  end

  def captured_amount(doc)
    captured = :not_called
    orig = GiroCode.method(:svg)
    GiroCode.define_singleton_method(:svg) { |**kw| captured = kw[:amount]; "<svg/>" }
    begin
      document_giro_code_brief(doc)
    ensure
      GiroCode.singleton_class.send(:remove_method, :svg)
      GiroCode.define_singleton_method(:svg, orig)
    end
    captured
  end

  test "#1171 GiroCode-Brief: Zahlbetrag versteht deutsches und englisches Dezimalformat" do
    assert_equal 1234.56.to_d, captured_amount(brief_with_zahlbetrag("1.234,56"))
    assert_equal 1234.56.to_d, captured_amount(brief_with_zahlbetrag("1234.56"))
  end

  test "#1171 GiroCode-Brief: ohne verwertbaren Zahlbetrag kein GiroCode" do
    assert_equal :not_called, captured_amount(brief_with_zahlbetrag("kein Betrag"))
    assert_equal :not_called, captured_amount(brief_with_zahlbetrag("0,00"))
  end

  test "#1171 Anschriftfeld: Kurzform ersetzt die Namenszeile, Titel ist der Default" do
    empf = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Max Mustermann",
                                 item_type: :person,
                                 file_path: "kb/#{SecureRandom.hex(4)}.md",
                                 content_hash: SecureRandom.hex(8))
    doc = Document.create!(kind: :brief, recipient_uuid: empf.uuid)
    assert_equal ["Max Mustermann"], doc.recipient_name_lines
    assert_equal "Max Mustermann", printable_recipient_lines(doc).first

    doc.update!(recipient_label: "Eheleute Mustermann")
    assert_equal ["Eheleute Mustermann"], doc.recipient_name_lines
    assert_equal "Eheleute Mustermann", printable_recipient_lines(doc).first
  end

  test "#1171 Anschriftfeld: ohne Empfänger Platzhalterzeile" do
    doc = Document.create!(kind: :brief)
    assert_equal ["Empfänger — kein KI gewählt"], printable_recipient_lines(doc)
  end
end
