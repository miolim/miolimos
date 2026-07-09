require "test_helper"

# #934: Dokument-Eingang — zweiphasiger Prozessor (Analyse → Review →
# Anlage). LLM + ZUGFeRD werden gestubbt; Phase 2 legt Beleg-KI,
# Eingangsrechnung mit Positionen/Artefakt/Parteien und Aufgaben an.
class Inbox::Processors::DocumentImportTest < ActiveSupport::TestCase
  LLM_EXTRACTION = {
    "doc_type" => "rechnung",
    "title" => "Stadtwerke — Abschlagsrechnung Juli",
    "sender" => { "name" => "Stadtwerke Beispielstadt", "vat_id" => "DE999888777",
                  "iban" => "DE02120300000000202051", "city" => "Beispielstadt" },
    "recipient_name" => "Hans Groth",
    "invoice" => {
      "number" => "SW-2026-0815", "issue_date" => "2026-07-01", "due_date" => "2026-07-15",
      "service_start" => "2026-06-01", "service_end" => "2026-06-30",
      "net_total" => 100.0, "gross_total" => 119.0,
      "lines" => [
        { "description" => "Abschlag Strom", "quantity" => 1, "unit" => nil, "unit_price" => 100.0, "tax_rate" => 19.0 }
      ]
    },
    "task_suggestions" => ["Abschlagsplan prüfen"],
    "confidence" => "hoch"
  }.freeze

  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Task",          %w[read create update delete])
    @proc = Inbox::Processors::DocumentImport.new
  end

  def make_item(payload: {})
    path = File.join(Dir.mktmpdir, "eingang.pdf")
    File.binwrite(path, "%PDF-1.4 fake content")
    InboxItem.create!(creator: @hans, source_kind: "pdf_upload", status: "pending",
                      external_path: path, title: "eingang.pdf", payload: payload)
  end

  # ZugferdReader im Test abschalten (kein venv-Zugriff, deterministisch).
  def without_zugferd(&block)
    original = ZugferdReader.method(:available?)
    ZugferdReader.define_singleton_method(:available?) { false }
    yield
  ensure
    ZugferdReader.singleton_class.send(:remove_method, :available?) rescue nil
    ZugferdReader.define_singleton_method(:available?, original) if original
  end

  # ZUGFeRD-Extraktion mit festen Daten stubben (Auto-Durchlauf-Pfad).
  def with_zugferd(data, &block)
    orig_avail  = ZugferdReader.method(:available?)
    orig_extract = ZugferdReader.method(:extract)
    ZugferdReader.define_singleton_method(:available?) { true }
    ZugferdReader.define_singleton_method(:extract) { |_path| data }
    yield
  ensure
    [[:available?, orig_avail], [:extract, orig_extract]].each do |name, orig|
      ZugferdReader.singleton_class.send(:remove_method, name) rescue nil
      ZugferdReader.define_singleton_method(name, orig) if orig
    end
  end

  test "applies? für pdf_upload und upload" do
    assert Inbox::Processors::DocumentImport.applies?(make_item)
    refute Inbox::Processors::DocumentImport.applies?(
      InboxItem.new(source_kind: "web_url"))
  end

  test "Phase 1 (LLM): landet in awaiting_confirmation mit Extraktion" do
    item = make_item
    stub_chat_client(LLM_EXTRACTION.to_json) do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    item.reload
    assert_equal "awaiting_confirmation", item.status
    cf = item.result["confirmation"]
    assert_equal "document_review", cf["reason"]
    assert_equal "rechnung", cf.dig("extraction", "doc_type")
    assert_equal "llm", cf.dig("extraction", "source")
    assert_equal "SW-2026-0815", cf.dig("extraction", "invoice", "number")
  end

  test "Phase 2: legt Beleg-KI, Eingangsrechnung + Positionen + Artefakt und Aufgabe an" do
    item = make_item
    stub_chat_client(LLM_EXTRACTION.to_json) do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    item.reload
    item.update!(payload: item.payload.merge(
      "confirm_import" => true,
      "confirmed_task_titles" => ["Eingangsrechnung prüfen/zahlen: Stadtwerke SW-2026-0815"]
    ))
    without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    item.reload
    assert_equal "processed", item.status

    # Beleg-KI
    ki = KnowledgeItem.find_by(title: "Stadtwerke — Abschlagsrechnung Juli")
    assert ki, "Beleg-KI muss angelegt sein"
    assert_equal "transcript", ki.item_type

    # Eingangsrechnung
    invoice = Invoice.find(item.result.dig("invoice", "id"))
    assert invoice.eingehend?
    assert invoice.offen?
    assert_equal "SW-2026-0815", invoice.number
    assert_equal Date.new(2026, 7, 15), invoice.due_date
    assert_equal 1, invoice.invoice_lines.count
    assert_equal BigDecimal("100"), invoice.net_total
    assert_equal 1, invoice.document_artifacts.count, "Original-PDF muss als Artefakt hängen"
    assert_equal "Invoice", invoice.document_artifacts.first.printable_type

    # Absender-Org wurde angelegt, inkl. starker Identifier
    issuer = invoice.issuer
    assert_equal "Stadtwerke Beispielstadt", issuer.title
    assert_equal %w[DE999888777], issuer.identifiers.where(label: "USt-IdNr").pluck(:value)

    # Aufgabe mit Fälligkeit + Beleg-Verweis
    task = Task.find_by("title LIKE ?", "Eingangsrechnung prüfen%")
    assert task
    assert_equal Date.new(2026, 7, 15), task.due_date
    assert_includes task.description.to_s, ki.title
  end

  test "Entitäten-Matching: bestehende Org via USt-IdNr wird wiederverwendet" do
    existing = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Stadtwerke (Alt-Name)",
                                     item_type: :organization, file_path: "x/sw-#{SecureRandom.hex(3)}.md",
                                     content_hash: "h", body: "")
    existing.identifiers.create!(label: "USt-IdNr", value: "DE999888777", position: 0)

    item = make_item
    stub_chat_client(LLM_EXTRACTION.to_json) do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    item.reload
    item.update!(payload: item.payload.merge("confirm_import" => true))
    without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }

    invoice = Invoice.find(item.reload.result.dig("invoice", "id"))
    assert_equal existing.uuid, invoice.issuer_uuid, "muss die bestehende Org matchen, nicht neu anlegen"
    refute KnowledgeItem.exists?(title: "Stadtwerke Beispielstadt")
  end

  test "Nicht-Rechnung: nur Beleg-KI, keine Invoice" do
    extraction = LLM_EXTRACTION.merge("doc_type" => "anschreiben", "invoice" => nil,
                                      "title" => "Behörde — Bescheid")
    item = make_item
    stub_chat_client(extraction.to_json) do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    item.reload
    item.update!(payload: item.payload.merge("confirm_import" => true))
    assert_no_difference -> { Invoice.count } do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    assert_equal "processed", item.reload.status
    assert KnowledgeItem.exists?(title: "Behörde — Bescheid")
  end

  # ── #934 Stufe 2 ──────────────────────────────────────────────────────

  ZUGFERD_DATA = {
    "number" => "ZF-100", "issue_date" => "2026-07-01", "due_date" => "2026-07-15",
    "seller" => { "name" => "Determi GmbH", "vat_id" => "DE111222333", "city" => "Kiel" },
    "buyer" => { "name" => "Hans" }, "iban" => "DE89370400440532013000",
    "service_start" => nil, "service_end" => nil,
    "net_total" => 50.0, "tax_total" => 9.5, "gross_total" => 59.5,
    "payment_terms" => "2% Skonto bei Zahlung binnen 10 Tagen",
    "lines" => [{ "description" => "Wartung", "quantity" => 1, "unit" => nil,
                  "unit_price" => 50.0, "tax_rate" => 19.0 }]
  }.freeze

  test "ZUGFeRD: läuft ohne Review durch — Invoice, Skonto-Feld und Standard-Aufgabe direkt" do
    item = make_item
    with_zugferd(ZUGFERD_DATA) do
      Inbox::Processors::DocumentImport.run(item, actor: @hans)
    end
    item.reload
    assert_equal "processed", item.status, "deterministische E-Rechnung braucht kein Review"

    invoice = Invoice.find(item.result.dig("invoice", "id"))
    assert invoice.eingehend?
    assert_equal "ZF-100", invoice.number
    assert_equal [["Zahlungsbedingungen", "2% Skonto bei Zahlung binnen 10 Tagen"]],
                 invoice.document_fields.map { |f| [f.label, f.value] }
    assert_equal 1, invoice.document_artifacts.count

    task = Task.find_by("title LIKE ?", "Eingangsrechnung prüfen%")
    assert task, "Standard-Aufgabe muss beim Auto-Durchlauf angelegt werden"
    assert_equal Date.new(2026, 7, 15), task.due_date
  end

  test "LLM-Pfad übernimmt payment_terms als Infoblock-Feld" do
    extraction = JSON.parse(LLM_EXTRACTION.to_json)
    extraction["invoice"]["payment_terms"] = "30 Tage netto"
    item = make_item
    stub_chat_client(extraction.to_json) do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    item.reload
    item.update!(payload: item.payload.merge("confirm_import" => true))
    without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    invoice = Invoice.find(item.reload.result.dig("invoice", "id"))
    assert_equal [["Zahlungsbedingungen", "30 Tage netto"]],
                 invoice.document_fields.map { |f| [f.label, f.value] }
  end

  test "suggested_processor_kind: Mail-Anhang → document_import, direkter Upload → pdf_bib_import" do
    mail_attachment = make_item(payload: { "communication_id" => 42 })
    assert_equal "document_import", mail_attachment.suggested_processor_kind
    direct = make_item
    assert_equal "pdf_bib_import", direct.suggested_processor_kind
  end
end
