require "test_helper"

# #532 Phase 2 (Hans, 2026-06-07): Theme-Werkbank — der Briefkopf wird aus
# dem gewählten Aussteller-KI (issuer) gespeist; ohne Aussteller steht ein
# Platzhalter. Deckt das Stammdaten→Dokument-Mapping ab.
class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "doc-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret", role: :admin
    )
    grant(@hans, "Task",          %w[read create update delete])
    grant(@hans, "KnowledgeItem", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "preview ohne Aussteller rendert Platzhalter-Briefkopf" do
    get "/documents/preview", params: { sample: "invoice" }
    assert_response :success
    assert_includes @response.body, "Kein Aussteller markiert"
  end

  test "preview mit Aussteller speist den Briefkopf aus den Stammdaten" do
    org = FileProxy.create(actor: @hans, title: "Meine Firma GmbH",
                           item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: org, issuer: true)
    org.identifiers.create!(label: "USt-IdNr", value: "DE999888777", position: 0)
    org.postal_addresses.create!(line1: "Musterstr. 1", postal_code: "20095", city: "Hamburg",
                                 position: 0, billing: true)
    org.contact_points.create!(kind: "email", value: "rechnung@firma.de", position: 1)

    get "/documents/preview", params: { sample: "invoice", issuer: org.uuid }
    assert_response :success
    body = @response.body
    assert_includes body, "Meine Firma GmbH"
    assert_includes body, "USt-IdNr. DE999888777"
    assert_includes body, "rechnung@firma.de"
    assert_includes body, "Musterstr. 1 · 20095 Hamburg"   # Adress-Fallback, Zeilen mit · verbunden
    refute_includes body, "Kein Aussteller markiert"
  end

  test "letter-Sample rendert DIN-5008-Anschreiben mit Anschriftfeld + Falzmarken" do
    get "/documents/preview", params: { sample: "letter" }
    assert_response :success
    body = @response.body
    assert_includes body, "din-page"
    assert_includes body, "din-address"       # Anschriftfeld
    assert_includes body, "din-fold-1"        # Falzmarke 105 mm
    assert_includes body, "din-hole"          # Lochmarke 148,5 mm
    assert_includes body, "Mit freundlichen Grüßen"
  end

  # #532 (2026-06-08): echte Document-Records datengetrieben rendern.
  # #547: AES-Signatur-Setup + Route vorhanden.
  test "signed_pdf-Route existiert und DocumentSigner ist aufrufbar" do
    doc = Document.create!(kind: :brief)
    assert_equal "/documents/#{doc.id}/signed_pdf", signed_pdf_document_path(doc)
    assert_includes [true, false], DocumentSigner.available?
  end

  # #532: final = gesperrt + festgeschriebene Stände.
  test "final sperrt Feld-Mutationen; Status zurück auf Entwurf entsperrt" do
    iss = FileProxy.create(actor: @hans, title: "Firma", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    doc = Document.create!(kind: :brief, subject: "Alt", status: :final)
    assert doc.locked?

    # Feld-Mutation (subject) wird ignoriert
    patch "/documents/#{doc.id}", params: { subject: "Neu" }
    assert_equal "Alt", doc.reload.subject

    # link wird abgelehnt
    post "/documents/#{doc.id}/link", params: { field: "issuer", value: iss.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :forbidden
    assert_nil doc.reload.issuer_uuid

    # Status zurück auf Entwurf ist erlaubt -> entsperrt
    patch "/documents/#{doc.id}", params: { status: "entwurf" }
    refute doc.reload.locked?
    patch "/documents/#{doc.id}", params: { subject: "Jetzt änderbar" }
    assert_equal "Jetzt änderbar", doc.reload.subject
  end

  # #556: Status-Wechsel schaltet den Editor live um (ohne Browser-Refresh).
  test "Status-Wechsel ersetzt den ganzen Editor-Bereich per Turbo-Stream (#556)" do
    doc = Document.create!(kind: :brief, subject: "X", status: :final)

    # final -> entwurf: ganzer Editor-Bereich wird ersetzt (Felder editierbar)
    patch "/documents/#{doc.id}", params: { status: "entwurf" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes @response.body, "document_editor_#{doc.id}"
    refute doc.reload.locked?

    # reiner Feldsave (kein Sperrwechsel): nur der Felder-Block
    patch "/documents/#{doc.id}", params: { subject: "Y" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes @response.body, "document_fields_#{doc.id}"
    refute_includes @response.body, "document_editor_#{doc.id}"

    # entwurf -> final: wieder ganzer Editor (jetzt read-only)
    patch "/documents/#{doc.id}", params: { status: "final" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes @response.body, "document_editor_#{doc.id}"
    assert doc.reload.locked?
  end

  test "archive_pdf nur bei final; artifact liefert gespeichertes PDF" do
    doc = Document.create!(kind: :brief, status: :entwurf)
    post "/documents/#{doc.id}/archive_pdf"
    assert_equal 0, doc.document_artifacts.count   # entwurf -> nicht festgeschrieben

    art = doc.document_artifacts.create!(pdf: "%PDF-1.4 fake".b, signed: true, creator: @hans)
    get "/documents/#{doc.id}/artifacts/#{art.id}"
    assert_response :success
    assert_equal "application/pdf", @response.media_type
    assert_includes @response.body, "%PDF-1.4"
  end

  test "show rendert ein Prosa-Dokument aus dem verlinkten Body-KI" do
    iss  = FileProxy.create(actor: @hans, title: "Firma GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    rec  = FileProxy.create(actor: @hans, title: "Muster GmbH", item_type: :organization, content: "")
    rec.postal_addresses.create!(line1: "Beispielweg 12", postal_code: "10117", city: "Berlin", position: 0)
    body = FileProxy.create(actor: @hans, title: "Brieftext",
                            item_type: :note, content: "Dies ist der **Brieftext** aus dem KI.")
    doc  = Document.create!(kind: :brief, issuer_uuid: iss.uuid, recipient_uuid: rec.uuid,
                            body_ki_uuid: body.uuid, subject: "Angebot", document_date: Date.new(2026, 6, 8))

    get "/documents/#{doc.id}"
    assert_response :success
    b = @response.body
    assert_includes b, "din-page"
    assert_includes b, "Muster GmbH"                 # Empfänger im Anschriftfeld
    assert_includes b, "Beispielweg 12"
    assert_includes b, "<strong>Brieftext</strong>"  # Body-KI als Markdown gerendert
    assert_includes b, "Mit freundlichen Grüßen"
    assert_includes b, "Firma GmbH"                  # Aussteller im Briefkopf
  end

  test "show rendert eine Rechnung mit Positionen + Steueraufschlüsselung" do
    iss = FileProxy.create(actor: @hans, title: "Firma GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    iss.identifiers.create!(label: "USt-IdNr", value: "DE123", position: 0)
    rec = FileProxy.create(actor: @hans, title: "Kunde AG", item_type: :organization, content: "")
    doc = Document.create!(kind: :rechnung, issuer_uuid: iss.uuid, recipient_uuid: rec.uuid,
                           number: "2026-0001", document_date: Date.new(2026, 6, 8))
    doc.invoice_lines.create!(description: "Beratung", quantity: 10, unit: "h", unit_price: 100, tax_rate: 19)
    doc.invoice_lines.create!(description: "Buch", quantity: 1, unit_price: 50, tax_rate: 7)

    get "/documents/#{doc.id}"
    assert_response :success
    b = @response.body
    assert_includes b, "Rechnung"
    assert_includes b, "Beratung"
    assert_includes b, "2026-0001"
    assert_includes b, "Nettobetrag"
    assert_includes b, "Gesamtbetrag"
    assert_includes b, "Kunde AG"
  end

  # #532 (2026-06-08): Liste/Detail/Anlegen — die Editor-Oberfläche.
  test "index rendert die Dokumentenliste als Stack-Blade" do
    iss = FileProxy.create(actor: @hans, title: "Firma GmbH", item_type: :organization, content: "")
    rec = FileProxy.create(actor: @hans, title: "Kunde AG",   item_type: :organization, content: "")
    Document.create!(kind: :brief, subject: "Hallo Welt", issuer_uuid: iss.uuid, recipient_uuid: rec.uuid)

    get "/documents"
    assert_response :success
    assert_includes @response.body, "stack_card_list:documents"
    assert_includes @response.body, "Hallo Welt"
    assert_includes @response.body, "Firma GmbH"
    assert_includes @response.body, "Kunde AG"
  end

  test "index mit document:<id> im Stack rendert das Detail-Blade (Post-Create-Pfad)" do
    doc = Document.create!(kind: :brief, subject: "Frischer Entwurf")
    get "/documents", params: { stack: "list:documents,document:#{doc.id}" }
    assert_response :success
    assert_includes @response.body, "stack_card_list:documents"
    assert_includes @response.body, "stack_card_document:#{doc.id}"
    assert_includes @response.body, "document_fields_#{doc.id}"
  end

  test "create legt einen Brief-Entwurf an und öffnet ihn im Stack" do
    assert_difference -> { Document.count }, 1 do
      post "/documents", params: { kind: "brief" }
    end
    doc = Document.last
    assert_equal "brief", doc.kind
    assert_equal "entwurf", doc.status
    assert_redirected_to documents_path(stack: "list:documents,document:#{doc.id}")
  end

  test "create lehnt noch nicht anlegbare Typen ab" do
    assert_no_difference -> { Document.count } do
      post "/documents", params: { kind: "angebot" }
    end
    assert_redirected_to documents_path
  end

  # #541: Rechnung ist jetzt anlegbar.
  test "create legt eine Rechnung an" do
    assert_difference -> { Document.count }, 1 do
      post "/documents", params: { kind: "rechnung" }
    end
    assert_equal "rechnung", Document.order(:id).last.kind
  end

  # #562: NDA ist jetzt anlegbar.
  test "create legt eine NDA an" do
    assert_difference -> { Document.count }, 1 do
      post "/documents", params: { kind: "nda" }
    end
    assert_equal "nda", Document.order(:id).last.kind
  end

  # #786: SEPA-Lastschriftmandat ist anlegbar und ist ein Prosa-Dokument.
  test "create legt ein SEPA-Lastschriftmandat an (Prosa)" do
    assert_difference -> { Document.count }, 1 do
      post "/documents", params: { kind: "lastschrift" }
    end
    doc = Document.order(:id).last
    assert_equal "lastschrift", doc.kind
    assert doc.prose?, "Lastschriftmandat muss ein Prosa-Body-Dokument sein"
    refute doc.invoice?
  end

  # #786: create_body_ki zieht den Vorlagentext aus der Daten-Vorlage
  # (Notiz-KI mit Tag vorlage:lastschrift), wie bei der NDA (#766).
  test "create_body_ki nutzt die vorlage:lastschrift-Vorlage" do
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Vorlage: SEPA-Mandat",
      item_type: :note, body: "## SEPA-Lastschriftmandat\n\nGläubiger: …",
      tags: ["vorlage:lastschrift"],
      file_path: "knowledge/vorlage-ls-#{SecureRandom.hex(3)}.md",
      content_hash: SecureRandom.hex(32), file_created_at: Time.current,
      file_updated_at: Time.current, indexed_at: Time.current)
    doc = Document.create!(kind: :lastschrift, status: :entwurf)
    post "/documents/#{doc.id}/create_body_ki"
    body_ki = KnowledgeItem.find_by(uuid: doc.reload.body_ki_uuid)
    assert body_ki, "Body-KI muss angelegt + verknüpft sein"
    assert_includes body_ki.body.to_s, "SEPA-Lastschriftmandat"
  end

  test "card rendert das Detail-Blade mit Feldern" do
    doc = Document.create!(kind: :brief, subject: "Betreff X")
    get "/documents/#{doc.id}/card"
    assert_response :success
    assert_includes @response.body, "stack_card_document:#{doc.id}"
    assert_includes @response.body, "Betreff X"
    assert_includes @response.body, "document_fields_#{doc.id}"
  end

  test "update speichert skalare Meta-Felder" do
    doc = Document.create!(kind: :brief)
    patch "/documents/#{doc.id}", params: { subject: "Neuer Betreff" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    patch "/documents/#{doc.id}", params: { salutation: "Hallo" }
    doc.reload
    assert_equal "Neuer Betreff", doc.subject
    assert_equal "Hallo", doc.salutation
  end

  test "suggest_links liefert Aussteller/Empfänger/Topic als {slug,label}" do
    iss = FileProxy.create(actor: @hans, title: "Acme GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    FileProxy.create(actor: @hans, title: "Acme Kunde", item_type: :organization, content: "")

    get "/documents/suggest_links", params: { kind: "issuer", q: "acme" }
    assert_response :success
    items = JSON.parse(@response.body)["items"]
    assert(items.any? { |i| i["label"] == "Acme GmbH" && i["slug"] == iss.uuid })
    # Empfänger-Scope umfasst alle Person/Org, nicht nur Aussteller
    get "/documents/suggest_links", params: { kind: "recipient", q: "acme" }
    assert_equal 2, JSON.parse(@response.body)["items"].size
  end

  test "link setzt und löst eine Verknüpfung (entity-picker)" do
    iss = FileProxy.create(actor: @hans, title: "Firma GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    doc = Document.create!(kind: :brief)

    post "/documents/#{doc.id}/link", params: { field: "issuer", value: iss.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_equal iss.uuid, doc.reload.issuer_uuid
    assert_includes @response.body, "document_issuer_chip_#{doc.id}"

    # leerer Wert = lösen
    post "/documents/#{doc.id}/link", params: { field: "issuer", value: "" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_nil doc.reload.issuer_uuid
  end

  test "update speichert Ihr/Unser Zeichen" do
    doc = Document.create!(kind: :brief)
    patch "/documents/#{doc.id}", params: { your_ref: "ABC-1" }
    patch "/documents/#{doc.id}", params: { our_ref: "HG-2026" }
    doc.reload
    assert_equal "ABC-1",   doc.your_ref
    assert_equal "HG-2026", doc.our_ref
  end

  test "create_body_ki legt ein Text-KI mit Titel-Schema an und verknüpft es" do
    rec = FileProxy.create(actor: @hans, title: "Kunde AG", item_type: :organization, content: "")
    doc = Document.create!(kind: :brief, recipient_uuid: rec.uuid, subject: "Angebot",
                           document_date: Date.new(2026, 6, 8))
    assert_difference -> { KnowledgeItem.where(item_type: "note").count }, 1 do
      post "/documents/#{doc.id}/create_body_ki",
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    doc.reload
    assert doc.body_ki.present?, "Body-KI wurde nicht verknüpft"
    assert_equal "Brief - 2026-06-08 Kunde AG Angebot", doc.body_ki.title
    assert_includes @response.body, "document_body_chip_#{doc.id}"
  end

  test "document_fields speichert freie Key-Value-Felder (Upsert + Replace)" do
    doc = Document.create!(kind: :brief)
    patch "/documents/#{doc.id}/document_fields", params: {
      fields: [{ label: "Auftragsnr.", value: "A-7" }, { label: "Ref", value: "R-1" }, { label: "", value: "" }]
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_equal 2, doc.reload.document_fields.count
    assert_equal [["Auftragsnr.", "A-7"], ["Ref", "R-1"]], doc.info_fields

    keep_id = doc.document_fields.first.id
    patch "/documents/#{doc.id}/document_fields", params: {
      fields: [{ id: keep_id, label: "Auftragsnr.", value: "A-99" }]
    }
    doc.reload
    assert_equal 1, doc.document_fields.count
    assert_equal keep_id, doc.document_fields.first.id   # id stabil (Upsert)
    assert_equal "A-99",  doc.document_fields.first.value
  end

  # #541: Rechnungspositionen upserten — Komma-Dezimal, Summen, Replace, Lock.
  test "invoice_lines: Positionen mit Komma-Dezimal, Summen, Upsert, Sperre" do
    doc = Document.create!(kind: :rechnung, status: :entwurf)
    patch "/documents/#{doc.id}/invoice_lines", params: {
      lines: [
        { description: "Beratung", quantity: "2,5", unit: "Std", unit_price: "80,00", tax_rate: "19" },
        { description: "Pauschale", quantity: "1", unit: "", unit_price: "100", tax_rate: "7" },
        { description: "", quantity: "", unit: "", unit_price: "", tax_rate: "19" } # leer -> ignoriert
      ]
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    doc.reload
    assert_equal 2, doc.invoice_lines.count
    l = doc.invoice_lines.ordered.first
    assert_equal BigDecimal("2.5"), l.quantity
    assert_equal BigDecimal("80"),  l.unit_price
    assert_equal BigDecimal("200"), l.net          # 2,5 × 80
    assert_equal BigDecimal("300"), doc.net_total  # 200 + 100

    keep = doc.invoice_lines.ordered.first.id
    patch "/documents/#{doc.id}/invoice_lines", params: {
      lines: [{ id: keep, description: "Beratung", quantity: "3", unit: "Std", unit_price: "80", tax_rate: "19" }]
    }
    doc.reload
    assert_equal 1, doc.invoice_lines.count
    assert_equal keep, doc.invoice_lines.first.id  # id stabil
    assert_equal BigDecimal("240"), doc.invoice_lines.first.net

    # final sperrt das Editieren der Positionen
    doc.update!(status: :final)
    patch "/documents/#{doc.id}/invoice_lines", params: { lines: [] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :forbidden
    assert_equal 1, doc.reload.invoice_lines.count
  end

  # #541: USt-Befreiung am Aussteller -> keine Umsatzsteuer in den Summen.
  test "vat_exempt Aussteller: keine USt, Brutto = Netto" do
    iss = FileProxy.create(actor: @hans, title: "Kleinunternehmer", item_type: :organization, content: "")
    iss.update_column(:vat_exempt, true)
    doc = Document.create!(kind: :rechnung, status: :entwurf, issuer_uuid: iss.uuid)
    doc.invoice_lines.create!(description: "Leistung", quantity: 1, unit_price: 100, tax_rate: 19, position: 0)
    assert doc.vat_exempt?
    assert_equal 0, doc.tax_total
    assert_equal BigDecimal("100"), doc.gross_total
    assert_empty doc.tax_breakdown
  end

  # #541: Rechnungsnummer + Leistungszeitraum (§14 UStG Pflichtfelder) speichern.
  test "update speichert Rechnungsnummer + Leistungszeitraum" do
    doc = Document.create!(kind: :rechnung)
    patch "/documents/#{doc.id}", params: { number: "2026-001", service_start: "2026-05-01", service_end: "2026-05-31" }
    doc.reload
    assert_equal "2026-001", doc.number
    assert_equal Date.new(2026, 5, 1),  doc.service_start
    assert_equal Date.new(2026, 5, 31), doc.service_end
  end

  # #541: USt-Befreiung am KI umschalten (DB-direkt).
  test "vat_exempt-Toggle setzt das KI-Flag" do
    ki = FileProxy.create(actor: @hans, title: "Firma X", item_type: :organization, content: "")
    patch "/knowledge_items/#{ki.uuid}/vat_exempt", params: { vat_exempt: "1" }
    assert ki.reload.vat_exempt?
    patch "/knowledge_items/#{ki.uuid}/vat_exempt", params: { vat_exempt: "0" }
    refute ki.reload.vat_exempt?
  end

  # #541: abrechenbare Projekt-Zeiten als Positionen übernehmen + Zuordnung.
  test "import_time_entries: Projekt-Zeiten werden Positionen, keine Doppel-Abrechnung" do
    topic = Topic.create!(name: "Projekt Z", creator: @hans)
    doc = Document.create!(kind: :rechnung, status: :entwurf, topic_id: topic.id)
    t1 = TimeEntry.log_manual!(actor: @hans, started_at: Time.zone.local(2026, 5, 2, 9), minutes: 90, topic: topic, billable: true, note: "Konzept")
    t2 = TimeEntry.log_manual!(actor: @hans, started_at: Time.zone.local(2026, 5, 3, 9), minutes: 60, topic: topic, billable: true, note: "Umsetzung")
    TimeEntry.log_manual!(actor: @hans, started_at: Time.zone.local(2026, 5, 4, 9), minutes: 30, topic: topic, billable: false)  # nicht abrechenbar
    assert_equal 2, TimeEntry.for_topic(topic).invoiceable.count

    post "/documents/#{doc.id}/import_time_entries",
         params: { rate: "80", time_entry_ids: [t1.id, t2.id] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    doc.reload
    assert_equal 2, doc.invoice_lines.count
    line1 = doc.invoice_lines.ordered.first
    assert_equal "Konzept", line1.description
    assert_equal BigDecimal("1.5"), line1.quantity
    assert_equal BigDecimal("80"),  line1.unit_price
    assert_equal BigDecimal("120"), line1.net           # 1,5 Std × 80
    assert_equal line1.id, t1.reload.invoice_line_id
    assert_equal 0, TimeEntry.for_topic(topic).invoiceable.count  # nichts mehr offen

    # Position löschen (Upsert) gibt die Zeit wieder frei (dependent: :nullify)
    keep = doc.invoice_lines.ordered.last.id
    patch "/documents/#{doc.id}/invoice_lines", params: {
      lines: [{ id: keep, description: "Umsetzung", quantity: "1", unit_price: "80", tax_rate: "19" }]
    }
    assert_nil t1.reload.invoice_line_id
    assert_equal 1, TimeEntry.for_topic(topic).invoiceable.count
  end

  # #541: ZUGFeRD-Payload sammelt die EN16931-Daten korrekt (reines Ruby).
  test "ZugferdGenerator.payload sammelt EN16931-Daten" do
    iss = FileProxy.create(actor: @hans, title: "Aussteller GmbH", item_type: :organization, content: "")
    iss.identifiers.create!(label: "USt-IdNr", value: "DE123456789", position: 0)
    iss.identifiers.create!(label: "IBAN",     value: "DE89370400440532013000", position: 1)
    rec = FileProxy.create(actor: @hans, title: "Kunde AG", item_type: :organization, content: "")
    doc = Document.create!(kind: :rechnung, number: "2026-009", status: :entwurf,
                           issuer_uuid: iss.uuid, recipient_uuid: rec.uuid, document_date: Date.new(2026, 6, 9))
    doc.invoice_lines.create!(description: "Beratung", quantity: 2, unit: "Std", unit_price: 50, tax_rate: 19, position: 0)

    p = ZugferdGenerator.payload(doc)
    assert_equal "2026-009", p[:number]
    assert_equal "2026-06-09", p[:issue_date]
    assert_equal "DE123456789", p[:seller][:vat_id]
    assert_equal "DE89370400440532013000", p[:iban]
    assert_equal "Kunde AG", p[:buyer][:name]
    assert_equal 1, p[:lines].size
    assert_equal "HUR", p[:lines][0][:unit]   # "Std" -> HUR
    assert_equal "100.00", p[:net_total]      # 2 × 50
    assert_equal "119.00", p[:gross_total]    # +19%
  end

  # #541 Compliance: Aussteller-spezifische Auto-Nummer (beim Setzen des
  # Ausstellers) + issuer_tax_ids/IBAN aus den IDs.
  test "Rechnungsnummer wird je Aussteller vergeben; tax_ids + IBAN aus den IDs" do
    iss = FileProxy.create(actor: @hans, title: "Meine GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    iss.identifiers.create!(label: "USt-IdNr", value: "DE123456789", position: 0)
    iss.identifiers.create!(label: "IBAN",     value: "DE89370400440532013000", position: 1)

    post "/documents", params: { kind: "rechnung" }
    doc = Document.order(:id).last
    assert_nil doc.number   # noch kein Aussteller -> noch keine Nummer

    post "/documents/#{doc.id}/link", params: { field: "issuer", value: iss.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    doc.reload
    assert_equal "#{Date.current.year}-001", doc.number   # erste Nummer dieses Ausstellers
    assert_equal [["USt-IdNr", "DE123456789"]], doc.issuer_tax_ids
    assert_equal "DE89370400440532013000", doc.issuer_iban

    # zweite Rechnung desselben Ausstellers -> -002
    post "/documents", params: { kind: "rechnung" }
    doc2 = Document.order(:id).last
    post "/documents/#{doc2.id}/link", params: { field: "issuer", value: iss.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "#{Date.current.year}-002", doc2.reload.number
  end

  # #541: Positions-Detail-Blade — leere Position + Zeit-Zuordnung (Menge = Stunden).
  test "invoice_line Blade: Position anlegen, Zeit zuordnen/lösen, Menge aus Stunden" do
    topic = Topic.create!(name: "Projekt P", creator: @hans)
    doc = Document.create!(kind: :rechnung, status: :entwurf, topic_id: topic.id)

    assert_difference -> { doc.invoice_lines.count }, 1 do
      post "/documents/#{doc.id}/add_invoice_line", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    line = doc.invoice_lines.ordered.last
    patch "/invoice_lines/#{line.id}", params: { unit_price: "100", description: "Beratung" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal BigDecimal("100"), line.reload.unit_price

    te = TimeEntry.log_manual!(actor: @hans, started_at: Time.zone.local(2026, 5, 2, 9), minutes: 90, topic: topic, billable: true)
    post "/invoice_lines/#{line.id}/assign_time", params: { time_entry_id: te.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal line.id, te.reload.invoice_line_id
    assert_equal BigDecimal("1.5"), line.reload.quantity   # 90 min = 1,5 Std
    assert_equal BigDecimal("150"), line.net               # 1,5 × 100
    assert_equal 0, TimeEntry.for_topic(topic).invoiceable.count

    get "/invoice_lines/#{line.id}/card"
    assert_response :success
    assert_includes @response.body, "stack_card_invoiceline:#{line.id}"

    delete "/invoice_lines/#{line.id}/unassign_time", params: { time_entry_id: te.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_nil te.reload.invoice_line_id
    assert_equal 1, TimeEntry.for_topic(topic).invoiceable.count

    # final sperrt die Zuordnung
    doc.update!(status: :final)
    post "/invoice_lines/#{line.id}/assign_time", params: { time_entry_id: te.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :forbidden
  end

  # #541: Rechnung blendet Anrede/Text aus, zeigt die Rechnungsnummer.
  test "card einer Rechnung: keine Anrede/Text, dafür Rechnungsnummer" do
    doc = Document.create!(kind: :rechnung, subject: "Leistung Mai")
    get "/documents/#{doc.id}/card"
    assert_response :success
    assert_includes @response.body, "Rechnungsnummer"
    assert_includes @response.body, "Rechnungspositionen"
    refute_includes @response.body, "Anrede"
  end

  test "select_identifiers: Aussteller-Nummer beim Empfänger ist Kandidat (Versichertennummer-Fall)" do
    me  = FileProxy.create(actor: @hans, title: "Ich Person", item_type: :person, content: "")
    kk  = FileProxy.create(actor: @hans, title: "Krankenkasse", item_type: :organization, content: "")
    other = FileProxy.create(actor: @hans, title: "Andere Kasse", item_type: :organization, content: "")
    # meine Versichertennummer bei der Krankenkasse (Aussteller hält, Empfänger = Gegenseite)
    vn  = me.identifiers.create!(label: "Versichertennummer", value: "Z123", counterparty_uuid: kk.uuid)
    # eine Nummer bei einer anderen Kasse -> KEIN Kandidat
    me.identifiers.create!(label: "Versichertennummer", value: "X999", counterparty_uuid: other.uuid)
    doc = Document.create!(kind: :brief, issuer_uuid: me.uuid, recipient_uuid: kk.uuid)

    assert_equal [vn.id], doc.identifier_candidates.map(&:id)

    patch "/documents/#{doc.id}/select_identifiers",
          params: { identifier_ids: [vn.id] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_equal [vn.id], doc.reload.shown_identifier_ids
    assert_includes doc.info_fields, ["Versichertennummer", "Z123"]

    # Nicht-Kandidat wird verworfen
    patch "/documents/#{doc.id}/select_identifiers", params: { identifier_ids: [999999] }
    assert_equal [], doc.reload.shown_identifier_ids
  end

  test "identifier_candidates umfasst auch Empfänger-Nummern bei mir (Kundennummer)" do
    me  = FileProxy.create(actor: @hans, title: "Meine Firma", item_type: :organization, content: "")
    kunde = FileProxy.create(actor: @hans, title: "Kunde AG", item_type: :organization, content: "")
    kn  = kunde.identifiers.create!(label: "Kundennummer", value: "K-42", counterparty_uuid: me.uuid)
    doc = Document.create!(kind: :rechnung, issuer_uuid: me.uuid, recipient_uuid: kunde.uuid)
    assert_equal [kn.id], doc.identifier_candidates.map(&:id)
  end

  test "link akzeptiert nur uuids im erlaubten Scope" do
    nonissuer = FileProxy.create(actor: @hans, title: "Nur Person", item_type: :person, content: "")
    doc = Document.create!(kind: :brief)
    # als Aussteller nicht erlaubt (kein issuer-Flag) -> bleibt nil
    post "/documents/#{doc.id}/link", params: { field: "issuer", value: nonissuer.uuid }
    assert_nil doc.reload.issuer_uuid
    # als Empfänger erlaubt (Person/Org)
    post "/documents/#{doc.id}/link", params: { field: "recipient", value: nonissuer.uuid }
    assert_equal nonissuer.uuid, doc.reload.recipient_uuid
  end
  # #622: Adresstyp — Briefe gehen an die Postadresse.
  test "DIN-Fenster nutzt die Postadresse, wenn markiert (#622)" do
    empf = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Groß GmbH", item_type: :organization,
                                 file_path: "x/gross.md", content_hash: "h", body: "", creator: @hans,
                                 published_at: Time.current)
    empf.postal_addresses.create!(line1: "Werksstraße 1", postal_code: "10115", city: "Berlin", position: 0)
    empf.postal_addresses.create!(line1: "Postfach 1234", postal_code: "10116", city: "Berlin",
                                  kind: :post, position: 1)
    doc = Document.create!(kind: :brief, status: :entwurf, creator: @hans,
                           recipient_uuid: empf.uuid, subject: "Testbetreff")
    get "/documents/#{doc.id}/card"
    assert_response :success
    lines = ApplicationController.helpers.document_recipient_lines(empf)
    assert_includes lines, "Postfach 1234"
    refute_includes lines, "Werksstraße 1"
  end

  # #623: Betreff-Feld zurück für Nicht-Rechnungen.
  test "Brief-Card zeigt Betreff-Feld, Rechnung nicht (#623)" do
    brief = Document.create!(kind: :brief, status: :entwurf, creator: @hans)
    get "/documents/#{brief.id}/card"
    assert_response :success
    assert_includes @response.body, "Betreff des Schreibens"

    re = Document.create!(kind: :rechnung, status: :entwurf, creator: @hans)
    get "/documents/#{re.id}/card"
    refute_includes @response.body, "Betreff des Schreibens"

    # #623 v2: NDAs brauchen das Feld ebenfalls nicht.
    nda = Document.create!(kind: :nda, status: :entwurf, creator: @hans)
    get "/documents/#{nda.id}/card"
    refute_includes @response.body, "Betreff des Schreibens"
  end

  # #624: Status→final schaltet den Festschreiben-Button LIVE frei.
  test "Status-Wechsel auf final streamt die Artefakt-Sektion mit (#624)" do
    doc = Document.create!(kind: :brief, status: :entwurf, creator: @hans)
    patch "/documents/#{doc.id}", params: { status: "final" }, as: :turbo_stream
    assert_response :success
    assert_includes @response.body, "document_artifacts_#{doc.id}"
    assert_includes @response.body, "Aktuellen Stand festschreiben"

    patch "/documents/#{doc.id}", params: { status: "entwurf" }, as: :turbo_stream
    assert_includes @response.body, "document_artifacts_#{doc.id}"
    refute_includes @response.body, "Aktuellen Stand festschreiben"
  end

  # #766 (Hans, 2026-06-23): NDA-Body-KI wird aus der Dokument-Vorlage in den
  # DATEN befüllt — eine Notiz-KI mit Tag "vorlage:nda" (nicht aus dem Code).
  test "create_body_ki befüllt den Body aus der Daten-Vorlage (vorlage:nda)" do
    FileProxy.create(actor: @hans, title: "Vorlage: NDA", item_type: :note,
                     content: "## § 1\nDer Erklärende behandelt Vertrauliche Informationen geheim.",
                     tags: ["vorlage:nda"])
    doc = Document.create!(kind: :nda, document_date: Date.new(2026, 6, 23))
    post "/documents/#{doc.id}/create_body_ki",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    bk = KnowledgeItem.find_by(uuid: doc.reload.body_ki_uuid)
    assert_includes bk.body.to_s, "Vertrauliche Informationen"
    assert_includes bk.body.to_s, "Erklärende"
  end

  test "create_body_ki lässt den Body leer, wenn keine Daten-Vorlage existiert" do
    doc = Document.create!(kind: :nda, document_date: Date.new(2026, 6, 23))
    post "/documents/#{doc.id}/create_body_ki",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    bk = KnowledgeItem.find_by(uuid: doc.reload.body_ki_uuid)
    assert_equal "", bk.body.to_s.strip
  end

  # ── #787: Dokumente/finale PDFs löschen ─────────────────────────────────
  test "destroy legt ein Dokument in den Papierkorb (Soft-Delete)" do
    doc = Document.create!(kind: :brief, subject: "Weg damit")
    delete "/documents/#{doc.id}", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    doc.reload
    assert doc.discarded?, "Dokument muss als gelöscht markiert sein"
    refute Document.exists?(doc.id), "default_scope muss gelöschte ausblenden"
    assert Document.with_discarded.exists?(doc.id)
  end

  test "restore holt ein Dokument aus dem Papierkorb" do
    doc = Document.create!(kind: :brief, subject: "Zurück")
    doc.discard!
    refute Document.exists?(doc.id)
    post "/documents/#{doc.id}/restore", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert Document.exists?(doc.id), "wiederhergestelltes Dokument muss wieder sichtbar sein"
    refute doc.reload.discarded?
  end

  test "trash listet gelöschte Dokumente" do
    live = Document.create!(kind: :brief, subject: "Aktiv")
    gone = Document.create!(kind: :brief, subject: "Gelöscht-Betreff")
    gone.discard!
    get "/documents/trash"
    assert_response :success
    assert_includes @response.body, "Gelöscht-Betreff"
    refute_includes @response.body, "Aktiv"
  end

  # ── #786 Inkr.2: SEPA-Mandat aus Stammdaten auto-befüllen ───────────────
  def org_ki(title)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title, item_type: :organization,
      file_path: "knowledge/orgs/#{SecureRandom.hex(3)}.md", content_hash: SecureRandom.hex(32),
      file_created_at: Time.current, file_updated_at: Time.current, indexed_at: Time.current)
  end

  test "effective_debtor_account: Auswahl bevorzugt, sonst erste des Ausstellers" do
    iss = org_ki("Schuldner GmbH")
    a1 = iss.bank_accounts.create!(iban: "DE89370400440532013000", position: 0)
    a2 = iss.bank_accounts.create!(iban: "DE02120300000000202051", position: 1)
    doc = Document.create!(kind: :lastschrift, issuer_uuid: iss.uuid)
    assert_equal a1.id, doc.effective_debtor_account.id, "ohne Wahl die erste"
    doc.update!(debtor_bank_account_id: a2.id)
    assert_equal a2.id, doc.effective_debtor_account.id, "gewählte gewinnt"
    # Wahl, die nicht zum Aussteller gehört, wird ignoriert (Fallback erste)
    fremd = org_ki("Fremd").bank_accounts.create!(iban: "DE10100000000000000000")
    doc.update!(debtor_bank_account_id: fremd.id)
    assert_equal a1.id, doc.effective_debtor_account.id
  end

  test "SEPA-Mandat-Render befüllt Schuldner/Gläubiger/IBAN + Pflichttext" do
    iss = org_ki("Schuldner GmbH")
    iss.bank_accounts.create!(iban: "DE89370400440532013000", bic: "COBADEFFXXX", bank_name: "Commerzbank", position: 0)
    rec = org_ki("Gläubiger AG")
    doc = Document.create!(kind: :lastschrift, issuer_uuid: iss.uuid, recipient_uuid: rec.uuid)
    html = ApplicationController.render(partial: "documents/render", locals: { document: doc })
    assert_includes html, "SEPA-Lastschriftmandat"
    assert_includes html, "Schuldner GmbH"
    assert_includes html, "Gläubiger AG"
    assert_includes html, "DE89 3704 0044 0532 0130 00"   # iban_pretty
    assert_includes html, "COBADEFFXXX"
    assert_includes html, "acht Wochen"                   # gesetzlicher Pflichttext
  end

  test "destroy_artifact löscht einen festgeschriebenen PDF-Stand" do
    doc = Document.create!(kind: :brief, status: :final)
    art = doc.document_artifacts.create!(pdf: "PDFBYTES", signed: false, creator: @hans)
    assert_difference -> { doc.document_artifacts.count }, -1 do
      delete "/documents/#{doc.id}/artifacts/#{art.id}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end
end
