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
    assert_equal "rechnung", invoice.document_type, "#1336: erkannte Belegart wird gespeichert, nicht verworfen"
    assert_equal "SW-2026-0815", invoice.number
    # #1336 Stufe 2: die erkannte Fälligkeit wird zur Zahlungspflicht.
    obligation = invoice.payment_obligations.sole
    assert_equal Date.new(2026, 7, 15), obligation.due_on
    assert_equal Date.new(2026, 7, 15), invoice.next_due_on
    assert_equal(-invoice.gross_total, obligation.amount, "eingehend = negativ")
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

  test "Entitäten-Matching: IBAN mit Leerzeichen in den Stammdaten matcht trotzdem (#941)" do
    existing = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Stadtwerke Konto-Match",
                                     item_type: :organization, file_path: "x/swk-#{SecureRandom.hex(3)}.md",
                                     content_hash: "h", body: "")
    existing.identifiers.create!(label: "IBAN", value: "DE02 1203 0000 0000 2020 51", position: 0)

    extraction = JSON.parse(LLM_EXTRACTION.to_json)
    extraction["sender"]["vat_id"] = nil   # nur die IBAN kann matchen
    item = make_item
    stub_chat_client(extraction.to_json) do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    item.reload
    item.update!(payload: item.payload.merge("confirm_import" => true))
    without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }

    invoice = Invoice.find(item.reload.result.dig("invoice", "id"))
    assert_equal existing.uuid, invoice.issuer_uuid, "gruppiert gepflegte IBAN muss matchen"
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

  # ── #1336 Stufe 1: Belegart ───────────────────────────────────────────

  # `bescheid` und `versicherung` sind eigene Belegarten und fallen nicht
  # mehr auf „sonstiges" zusammen. Ohne Zahlbetrag entsteht kein Beleg —
  # seit #1338 aber nicht mehr wegen der Belegart, sondern weil nichts zu
  # zahlen ist (der Fall Anschreiben / Mietvertrag / Kontoauszug).
  test "ohne Zahlbetrag entsteht keine Invoice, die Belegart bleibt erhalten" do
    extraction = LLM_EXTRACTION.merge("doc_type" => "bescheid", "invoice" => nil,
                                      "title" => "Stadt — Abwasser-Festsetzungsbescheid")
    item = make_item
    stub_chat_client(extraction.to_json) do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    item.reload
    assert_equal "bescheid", item.result.dig("confirmation", "extraction", "doc_type")

    item.update!(payload: item.payload.merge("confirm_import" => true))
    assert_no_difference -> { Invoice.count } do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
  end

  # ── #1338: der Zahlbetrag entscheidet, nicht die Belegart ─────────────

  # Ein bestätigtes Dokument durch beide Phasen schicken und den erzeugten
  # Beleg (oder nil) zurückgeben.
  def import!(extraction)
    item = make_item
    stub_chat_client(extraction.to_json) do
      without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    end
    item.reload.update!(payload: item.payload.merge("confirm_import" => true))
    without_zugferd { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    id = item.reload.result.dig("invoice", "id")
    id && Invoice.find(id)
  end

  # Der Prüffall, der vorher gar nicht ging: kein „rechnung", trotzdem ein
  # Zahlbetrag — und damit ein Eingangsbeleg.
  test "Versicherungsschein mit Beitrag wird zum Beleg mit einer Zahlungspflicht" do
    extraction = JSON.parse(LLM_EXTRACTION.to_json)
                     .merge("doc_type" => "versicherung", "title" => "Allianz — Gebäudeversicherung")
    extraction["invoice"]["number"] = "POL-4711"
    invoice = import!(extraction)

    assert invoice, "ein Beitrag ist ein Zahlbetrag — daraus entsteht ein Beleg"
    assert_equal "versicherung", invoice.document_type, "die Art bleibt für die Ablage erhalten"
    assert_equal 1, invoice.payment_obligations.count
    assert_equal Date.new(2026, 7, 15), invoice.next_due_on
  end

  # Der Kern der Aufgabe: Ein Bescheid MIT Forderung wird zum Beleg — und der
  # Betrag kommt aus den Positionen, nicht aus einer Bemessungsgrundlage.
  test "Grunderwerbsteuerbescheid wird zum Beleg über die festgesetzte Steuer" do
    extraction = JSON.parse(LLM_EXTRACTION.to_json)
                     .merge("doc_type" => "bescheid", "title" => "Finanzamt — Grunderwerbsteuer")
    extraction["invoice"].merge!(
      "number" => "GrESt-2026-77", "due_date" => "2026-09-01",
      "net_total" => 22_750.0, "gross_total" => 22_750.0,
      "lines" => [{ "description" => "Grunderwerbsteuer 6,5 %", "quantity" => 1,
                    "unit" => nil, "unit_price" => 22_750.0, "tax_rate" => 0.0 }]
    )
    invoice = import!(extraction)

    assert invoice
    assert_equal "bescheid", invoice.document_type
    assert_equal BigDecimal("22750"), invoice.gross_total
    assert_equal BigDecimal("-22750"), invoice.payment_obligations.sole.amount
  end

  # Ohne erkannte Fälligkeit entsteht eine Pflicht OHNE TERMIN — ein offener
  # Posten ohne Frist, keine Lücke.
  #
  # Die erste Fassung dieses Tests verlangte hier gar keine Pflicht. Das war
  # derselbe Fehlschluss, den #1338 beseitigt: Die fehlende Fälligkeit stand
  # als Ersatz dafür, dass der Beleg keine eigene Forderung begründet. Im
  # Fork-Bestand haben 29 von 64 Eingangsbelegen Zahlungen ohne Fälligkeit —
  # die wären lautlos aus allen Listen gefallen.
  test "Zahlbetrag ohne erkannte Fälligkeit ergibt eine Pflicht ohne Termin" do
    extraction = JSON.parse(LLM_EXTRACTION.to_json)
                     .merge("doc_type" => "bescheid", "title" => "ZVO — Abwasser-Festsetzung")
    extraction["invoice"]["due_date"] = nil
    invoice = import!(extraction)

    assert invoice, "der Betrag steht da — der Beleg entsteht"
    pflicht = invoice.payment_obligations.sole
    assert_nil pflicht.due_on, "ohne Frist, aber vorhanden"
    assert_equal(-invoice.gross_total, pflicht.amount)
    assert_equal "offen", invoice.payment_status, "ein offener Posten ohne Termin"
    assert_not invoice.overdue?, "ohne Fälligkeit wird nicht gemahnt"
    assert_not Invoice.overdue.exists?(id: invoice.id)
  end

  # Ein Beleg OHNE Zahlbetrag entsteht gar nicht erst als Beleg — und wenn er
  # von Hand angelegt wird, bleibt er ohne Pflicht und damit ohne Zahlstatus.
  test "ohne Betrag keine Zahlungspflicht" do
    beleg = Invoice.create!(kind: :rechnung, direction: :eingehend, document_type: :bescheid)
    @proc.send(:build_payment_obligations, beleg, { "due_date" => "2026-09-01" })

    assert_empty beleg.payment_obligations
    assert_nil   beleg.payment_status
  end

  # Eine Gutschrift ist auch ein Zahlbetrag — das Vorzeichen darf das
  # Kriterium nicht aushebeln.
  test "negativer Betrag zählt als Zahlbetrag" do
    extraction = JSON.parse(LLM_EXTRACTION.to_json)
    extraction["invoice"].merge!("net_total" => -100.0, "gross_total" => -119.0,
                                 "lines" => [{ "description" => "Gutschrift", "quantity" => 1,
                                               "unit" => nil, "unit_price" => -100.0, "tax_rate" => 19.0 }])
    assert Inbox::Processors::DocumentImport.payment_relevant?(extraction)
  end

  # Der Erweiterungspunkt für den Fork: Er hängt dort seine Regel ein
  # (Vorauszahlungen eines laufenden Vertrags gehören dem Vertrag, nicht dem
  # Bescheid). Überschreibt jemand die Methode, entsteht keine Pflicht — der
  # Beleg selbst aber schon.
  test "build_payment_obligations ist die einzige Stelle und überschreibbar" do
    ohne_pflichten = Class.new(Inbox::Processors::DocumentImport) do
      def build_payment_obligations(_invoice, _inv) = nil
    end
    item = make_item
    stub_chat_client(LLM_EXTRACTION.to_json) do
      without_zugferd { ohne_pflichten.run(item, actor: @hans) }
    end
    item.reload.update!(payload: item.payload.merge("confirm_import" => true))
    without_zugferd { ohne_pflichten.run(item, actor: @hans) }

    invoice = Invoice.find(item.reload.result.dig("invoice", "id"))
    assert_empty invoice.payment_obligations, "der Fork kann die Erzeugung unterbinden"
    assert_equal BigDecimal("119"), invoice.gross_total, "der Beleg entsteht trotzdem"
  end

  # Die zwei Sätze sind im Fork-Betrieb teuer bezahlt worden und dürfen nicht
  # stillschweigend aus dem Prompt verschwinden.
  test "der Extraktions-Prompt hängt an der Zahlungspflicht, nicht am Typ" do
    prompt = Inbox::Processors::DocumentImport.new.send(:extraction_prompt)
    assert_includes prompt, "Zahlungspflicht begründet"
    assert_includes prompt, "Bemessungsgrundlage"
    assert_includes prompt, "mindestens EINE Position"
  end

  # ZUGFeRD läuft ohne Review durch — auch dort muss die Art am Beleg landen.
  test "ZUGFeRD-Beleg bekommt die Belegart rechnung" do
    item = make_item
    zugferd = { "seller" => { "name" => "Elektro Meier", "vat_id" => "DE111222333", "city" => "Musterstadt" },
                "buyer" => { "name" => "Hans Groth" }, "number" => "R-2026-7",
                "issue_date" => "2026-07-02", "due_date" => "2026-07-16",
                "net_total" => 50.0, "gross_total" => 59.5,
                "lines" => [{ "description" => "Montage", "quantity" => 1, "unit_price" => 50.0, "tax_rate" => 19.0 }] }
    with_zugferd(zugferd) { Inbox::Processors::DocumentImport.run(item, actor: @hans) }
    invoice = Invoice.find(item.reload.result.dig("invoice", "id"))
    assert_equal "rechnung", invoice.document_type
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
