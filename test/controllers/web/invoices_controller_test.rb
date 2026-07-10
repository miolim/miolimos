require "test_helper"

# #926: Rechnung/Angebot als eigene Entität — Editor, Positionen, Zeiten-
# Import, Nummernkreis, Sperre, e-Rechnung. Vorher Teil des Document-Modells
# (Strecken aus documents_controller_test hierher umgezogen).
class InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "inv-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret", role: :admin
    )
    grant(@hans, "Task",          %w[read create update delete])
    grant(@hans, "KnowledgeItem", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "index rendert die Rechnungsliste als Stack-Blade" do
    iss = FileProxy.create(actor: @hans, title: "Firma GmbH", item_type: :organization, content: "")
    rec = FileProxy.create(actor: @hans, title: "Kunde AG",   item_type: :organization, content: "")
    Invoice.create!(kind: :rechnung, number: "2026-077", issuer_uuid: iss.uuid, recipient_uuid: rec.uuid)

    get "/invoices"
    assert_response :success
    assert_includes @response.body, "stack_card_list:invoices"
    assert_includes @response.body, "2026-077"
    assert_includes @response.body, "Firma GmbH"
    assert_includes @response.body, "Kunde AG"
  end

  test "create legt einen Rechnungs-Entwurf an und öffnet ihn im Stack" do
    assert_difference -> { Invoice.count }, 1 do
      post "/invoices", params: { kind: "rechnung" }
    end
    invoice = Invoice.last
    assert_equal "rechnung", invoice.kind
    assert_equal "entwurf", invoice.status
    assert_nil invoice.number   # noch kein Aussteller -> noch keine Nummer
    assert_redirected_to invoices_path(stack: "list:invoices,invoice:#{invoice.id}")
  end

  test "create legt ein Angebot an" do
    assert_difference -> { Invoice.count }, 1 do
      post "/invoices", params: { kind: "angebot" }
    end
    assert_equal "angebot", Invoice.order(:id).last.kind
  end

  test "card rendert das Detail-Blade: Rechnungsnummer + Positionen, keine Anrede" do
    invoice = Invoice.create!(kind: :rechnung, subject: "Leistung Mai")
    get "/invoices/#{invoice.id}/card"
    assert_response :success
    assert_includes @response.body, "stack_card_invoice:#{invoice.id}"
    assert_includes @response.body, "Rechnungsnummer"
    assert_includes @response.body, "Rechnungspositionen"
    refute_includes @response.body, "Anrede"
  end

  test "show rendert eine Rechnung mit Positionen + Steueraufschlüsselung" do
    iss = FileProxy.create(actor: @hans, title: "Firma GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    iss.identifiers.create!(label: "USt-IdNr", value: "DE123", position: 0)
    rec = FileProxy.create(actor: @hans, title: "Kunde AG", item_type: :organization, content: "")
    invoice = Invoice.create!(kind: :rechnung, issuer_uuid: iss.uuid, recipient_uuid: rec.uuid,
                              number: "2026-0001", document_date: Date.new(2026, 6, 8))
    invoice.invoice_lines.create!(description: "Beratung", quantity: 10, unit: "h", unit_price: 100, tax_rate: 19)
    invoice.invoice_lines.create!(description: "Buch", quantity: 1, unit_price: 50, tax_rate: 7)

    get "/invoices/#{invoice.id}"
    assert_response :success
    b = @response.body
    assert_includes b, "Rechnung"
    assert_includes b, "Beratung"
    assert_includes b, "2026-0001"
    assert_includes b, "Nettobetrag"
    assert_includes b, "Gesamtbetrag"
    assert_includes b, "Kunde AG"
    assert_includes b, "din-page"
  end

  # #541: Rechnungsnummer + Leistungszeitraum (§14 UStG Pflichtfelder) speichern.
  test "update speichert Rechnungsnummer + Leistungszeitraum" do
    invoice = Invoice.create!(kind: :rechnung)
    patch "/invoices/#{invoice.id}", params: { number: "2026-001", service_start: "2026-05-01", service_end: "2026-05-31" }
    invoice.reload
    assert_equal "2026-001", invoice.number
    assert_equal Date.new(2026, 5, 1),  invoice.service_start
    assert_equal Date.new(2026, 5, 31), invoice.service_end
  end

  # #541: Rechnungspositionen upserten — Komma-Dezimal, Summen, Replace, Lock.
  test "invoice_lines: Positionen mit Komma-Dezimal, Summen, Upsert, Sperre" do
    invoice = Invoice.create!(kind: :rechnung, status: :entwurf)
    patch "/invoices/#{invoice.id}/invoice_lines", params: {
      lines: [
        { description: "Beratung", quantity: "2,5", unit: "Std", unit_price: "80,00", tax_rate: "19" },
        { description: "Pauschale", quantity: "1", unit: "", unit_price: "100", tax_rate: "7" },
        { description: "", quantity: "", unit: "", unit_price: "", tax_rate: "19" } # leer -> ignoriert
      ]
    }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    invoice.reload
    assert_equal 2, invoice.invoice_lines.count
    l = invoice.invoice_lines.ordered.first
    assert_equal BigDecimal("2.5"), l.quantity
    assert_equal BigDecimal("80"),  l.unit_price
    assert_equal BigDecimal("200"), l.net              # 2,5 × 80
    assert_equal BigDecimal("300"), invoice.net_total  # 200 + 100

    keep = invoice.invoice_lines.ordered.first.id
    patch "/invoices/#{invoice.id}/invoice_lines", params: {
      lines: [{ id: keep, description: "Beratung", quantity: "3", unit: "Std", unit_price: "80", tax_rate: "19" }]
    }
    invoice.reload
    assert_equal 1, invoice.invoice_lines.count
    assert_equal keep, invoice.invoice_lines.first.id  # id stabil
    assert_equal BigDecimal("240"), invoice.invoice_lines.first.net

    # final sperrt das Editieren der Positionen
    invoice.update!(status: :final)
    patch "/invoices/#{invoice.id}/invoice_lines", params: { lines: [] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :forbidden
    assert_equal 1, invoice.reload.invoice_lines.count
  end

  # #541: USt-Befreiung am Aussteller -> keine Umsatzsteuer in den Summen.
  test "vat_exempt Aussteller: keine USt, Brutto = Netto" do
    iss = FileProxy.create(actor: @hans, title: "Kleinunternehmer", item_type: :organization, content: "")
    iss.update_column(:vat_exempt, true)
    invoice = Invoice.create!(kind: :rechnung, status: :entwurf, issuer_uuid: iss.uuid)
    invoice.invoice_lines.create!(description: "Leistung", quantity: 1, unit_price: 100, tax_rate: 19, position: 0)
    assert invoice.vat_exempt?
    assert_equal 0, invoice.tax_total
    assert_equal BigDecimal("100"), invoice.gross_total
    assert_empty invoice.tax_breakdown
  end

  # #541: abrechenbare Projekt-Zeiten als Positionen übernehmen + Zuordnung.
  test "import_time_entries: Projekt-Zeiten werden Positionen, keine Doppel-Abrechnung" do
    topic = Topic.create!(name: "Projekt Z", creator: @hans)
    invoice = Invoice.create!(kind: :rechnung, status: :entwurf, topic_id: topic.id)
    t1 = TimeEntry.log_manual!(actor: @hans, started_at: Time.zone.local(2026, 5, 2, 9), minutes: 90, topic: topic, billable: true, note: "Konzept")
    t2 = TimeEntry.log_manual!(actor: @hans, started_at: Time.zone.local(2026, 5, 3, 9), minutes: 60, topic: topic, billable: true, note: "Umsetzung")
    TimeEntry.log_manual!(actor: @hans, started_at: Time.zone.local(2026, 5, 4, 9), minutes: 30, topic: topic, billable: false)  # nicht abrechenbar
    assert_equal 2, TimeEntry.for_topic(topic).invoiceable.count

    post "/invoices/#{invoice.id}/import_time_entries",
         params: { rate: "80", time_entry_ids: [t1.id, t2.id] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    invoice.reload
    assert_equal 2, invoice.invoice_lines.count
    line1 = invoice.invoice_lines.ordered.first
    assert_equal "Konzept", line1.description
    assert_equal BigDecimal("1.5"), line1.quantity
    assert_equal BigDecimal("80"),  line1.unit_price
    assert_equal BigDecimal("120"), line1.net           # 1,5 Std × 80
    assert_equal line1.id, t1.reload.invoice_line_id
    assert_equal 0, TimeEntry.for_topic(topic).invoiceable.count  # nichts mehr offen

    # Position löschen (Upsert) gibt die Zeit wieder frei (dependent: :nullify)
    keep = invoice.invoice_lines.ordered.last.id
    patch "/invoices/#{invoice.id}/invoice_lines", params: {
      lines: [{ id: keep, description: "Umsetzung", quantity: "1", unit_price: "80", tax_rate: "19" }]
    }
    assert_nil t1.reload.invoice_line_id
    assert_equal 1, TimeEntry.for_topic(topic).invoiceable.count
  end

  # #541 Compliance: Aussteller-spezifische Auto-Nummer (beim Setzen des
  # Ausstellers) + issuer_tax_ids/IBAN aus den IDs.
  test "Rechnungsnummer wird je Aussteller vergeben; tax_ids + IBAN aus den IDs" do
    iss = FileProxy.create(actor: @hans, title: "Meine GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    iss.identifiers.create!(label: "USt-IdNr", value: "DE123456789", position: 0)
    iss.identifiers.create!(label: "IBAN",     value: "DE89370400440532013000", position: 1)

    post "/invoices", params: { kind: "rechnung" }
    invoice = Invoice.order(:id).last
    assert_nil invoice.number   # noch kein Aussteller -> noch keine Nummer

    post "/invoices/#{invoice.id}/link", params: { field: "issuer", value: iss.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    invoice.reload
    assert_equal "#{Date.current.year}-001", invoice.number   # erste Nummer dieses Ausstellers
    assert_equal [["USt-IdNr", "DE123456789"]], invoice.issuer_tax_ids
    assert_equal "DE89370400440532013000", invoice.issuer_iban

    # zweite Rechnung desselben Ausstellers -> -002
    post "/invoices", params: { kind: "rechnung" }
    invoice2 = Invoice.order(:id).last
    post "/invoices/#{invoice2.id}/link", params: { field: "issuer", value: iss.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "#{Date.current.year}-002", invoice2.reload.number
  end

  # #541: Positions-Detail-Blade — leere Position + Zeit-Zuordnung (Menge = Stunden).
  test "invoice_line Blade: Position anlegen, Zeit zuordnen/lösen, Menge aus Stunden" do
    topic = Topic.create!(name: "Projekt P", creator: @hans)
    invoice = Invoice.create!(kind: :rechnung, status: :entwurf, topic_id: topic.id)

    assert_difference -> { invoice.invoice_lines.count }, 1 do
      post "/invoices/#{invoice.id}/add_invoice_line", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    line = invoice.invoice_lines.ordered.last
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
    invoice.update!(status: :final)
    post "/invoice_lines/#{line.id}/assign_time", params: { time_entry_id: te.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :forbidden
  end

  test "identifier_candidates umfasst auch Empfänger-Nummern bei mir (Kundennummer)" do
    me    = FileProxy.create(actor: @hans, title: "Meine Firma", item_type: :organization, content: "")
    kunde = FileProxy.create(actor: @hans, title: "Kunde AG", item_type: :organization, content: "")
    kn    = kunde.identifiers.create!(label: "Kundennummer", value: "K-42", counterparty_uuid: me.uuid)
    invoice = Invoice.create!(kind: :rechnung, issuer_uuid: me.uuid, recipient_uuid: kunde.uuid)
    assert_equal [kn.id], invoice.identifier_candidates.map(&:id)
  end

  # #532: final = gesperrt; Sperr-/Editor-Streams wie beim Anschreiben.
  test "final sperrt Feld-Mutationen; Status-Wechsel streamt den Editor" do
    invoice = Invoice.create!(kind: :rechnung, number: "ALT", status: :final)
    patch "/invoices/#{invoice.id}", params: { number: "NEU" }
    assert_equal "ALT", invoice.reload.number

    patch "/invoices/#{invoice.id}", params: { status: "entwurf" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes @response.body, "invoice_editor_#{invoice.id}"
    refute invoice.reload.locked?

    patch "/invoices/#{invoice.id}", params: { number: "NEU" }
    assert_equal "NEU", invoice.reload.number
  end

  test "archive_pdf nur bei final; artifact liefert gespeichertes PDF" do
    invoice = Invoice.create!(kind: :rechnung, status: :entwurf)
    post "/invoices/#{invoice.id}/archive_pdf"
    assert_equal 0, invoice.document_artifacts.count   # entwurf -> nicht festgeschrieben

    art = invoice.document_artifacts.create!(pdf: "%PDF-1.4 fake".b, signed: true, creator: @hans)
    get "/invoices/#{invoice.id}/artifacts/#{art.id}"
    assert_response :success
    assert_equal "application/pdf", @response.media_type
    assert_includes @response.body, "%PDF-1.4"
  end

  # ── #934: Eingangsrechnungen (direction) ────────────────────────────────
  test "eingehende Rechnung: keine Auto-Nummer beim Aussteller-Link" do
    iss = FileProxy.create(actor: @hans, title: "Fremdfirma GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: iss, issuer: true)
    invoice = Invoice.create!(kind: :rechnung, direction: :eingehend)
    post "/invoices/#{invoice.id}/link", params: { field: "issuer", value: iss.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_nil invoice.reload.number, "eingehende Rechnungen bekommen KEINE Nummer aus dem Nummernkreis"
  end

  test "update speichert Fälligkeit + Zahlstatus (eingehend)" do
    invoice = Invoice.create!(kind: :rechnung, direction: :eingehend)
    patch "/invoices/#{invoice.id}", params: { due_date: "2026-08-15" }
    patch "/invoices/#{invoice.id}", params: { payment_status: "bezahlt" }
    invoice.reload
    assert_equal Date.new(2026, 8, 15), invoice.due_date
    assert invoice.bezahlt?
  end

  test "card einer Eingangsrechnung: Eingang-Badge, keine Render-Aktionen" do
    invoice = Invoice.create!(kind: :rechnung, direction: :eingehend, number: "SW-11")
    get "/invoices/#{invoice.id}/card"
    assert_response :success
    assert_includes @response.body, "Eingang"
    refute_includes @response.body, rendered_pdf_invoice_path(invoice)
    assert_includes @response.body, "Fällig am"
  end

  # ── #964: Beleg (PDF) manuell an Eingangsrechnung hängen ─────────────────
  test "upload_artifact: PDF an Eingangsrechnung, danach in der Beleg-Sektion" do
    invoice = Invoice.create!(kind: :rechnung, direction: :eingehend, number: "UP-1")
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.7 test"), "application/pdf",
                                       original_filename: "beleg.pdf")
    assert_difference -> { invoice.document_artifacts.count }, 1 do
      post "/invoices/#{invoice.id}/upload_artifact", params: { file: pdf },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_equal "%PDF-1.7 test", invoice.document_artifacts.last.pdf
    assert_includes @response.body, "invoice_artifacts_#{invoice.id}"
  end

  test "upload_artifact: ausgehend abgelehnt, Nicht-PDF abgelehnt" do
    aus = Invoice.create!(kind: :rechnung, direction: :ausgehend)
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.7"), "application/pdf",
                                       original_filename: "x.pdf")
    assert_no_difference -> { DocumentArtifact.count } do
      post "/invoices/#{aus.id}/upload_artifact", params: { file: pdf },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :unprocessable_content

    ein = Invoice.create!(kind: :rechnung, direction: :eingehend)
    txt = Rack::Test::UploadedFile.new(StringIO.new("kein pdf"), "application/pdf",
                                       original_filename: "fake.pdf")
    assert_no_difference -> { DocumentArtifact.count } do
      post "/invoices/#{ein.id}/upload_artifact", params: { file: txt },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success   # Toast mit Fehlermeldung
    assert_includes @response.body, "Nur PDF-Dateien"
  end

  # #946 Folge (Hans): Eingangsrechnungen haben keinen Status-Lebenszyklus.
  test "card einer Eingangsrechnung: kein Status-Select, kein Festschreiben, Heading Beleg" do
    ein = Invoice.create!(kind: :rechnung, direction: :eingehend, number: "SW-12")
    get "/invoices/#{ein.id}/card"
    assert_response :success
    refute_includes @response.body, 'name="status"'
    refute_includes @response.body, "festzuschreiben"          # Archive-Hint
    refute_includes @response.body, archive_pdf_invoice_path(ein)
    assert_includes @response.body, "Beleg"
    refute_includes @response.body, "Festgeschriebene Stände"

    aus = Invoice.create!(kind: :rechnung, direction: :ausgehend)
    get "/invoices/#{aus.id}/card"
    assert_includes @response.body, 'name="status"'
    assert_includes @response.body, "Festgeschriebene Stände"
  end

  test "Liste: Eingangsrechnung im Entwurf zeigt kein Entwurf-Badge" do
    Invoice.create!(kind: :rechnung, direction: :eingehend, status: :entwurf, number: "EIN-BADGE-1")
    get "/invoices/list_card"
    assert_response :success
    row = @response.body[/id="invoice_row_#{Invoice.find_by(number: 'EIN-BADGE-1').id}".*?<\/li>/m]
    assert row, "Listenzeile nicht gefunden"
    assert_includes row, "Eingang"
    refute_includes row, "Entwurf"
  end

  # ── #946: Eingangsrechnung manuell anlegen ───────────────────────────────
  test "create mit direction=eingehend legt eine Eingangsrechnung an" do
    assert_difference -> { Invoice.count }, 1 do
      post "/invoices", params: { kind: "rechnung", direction: "eingehend" }
    end
    invoice = Invoice.order(:id).last
    assert invoice.eingehend?
    assert_nil invoice.number   # Nummer kommt vom fremden Aussteller
  end

  test "create: Angebote bleiben ausgehend, direction wird ignoriert" do
    post "/invoices", params: { kind: "angebot", direction: "eingehend" }
    assert Invoice.order(:id).last.ausgehend?
  end

  test "Aussteller-Picker: eingehend schlägt Personen/Orgs vor, ausgehend nur eigene Firmen" do
    own = FileProxy.create(actor: @hans, title: "Eigene GmbH", item_type: :organization, content: "")
    FileProxy.update(actor: @hans, knowledge_item: own, issuer: true)
    FileProxy.create(actor: @hans, title: "Stadtwerke", item_type: :organization, content: "")

    get "/invoices/suggest_links", params: { kind: "issuer", q: "stadt" }
    assert_empty JSON.parse(@response.body)["items"]

    get "/invoices/suggest_links", params: { kind: "issuer", q: "stadt", direction: "eingehend" }
    labels = JSON.parse(@response.body)["items"].map { |i| i["label"] }
    assert_includes labels, "Stadtwerke"
  end

  test "link: Eingangsrechnung akzeptiert fremde Org als Aussteller, ausgehend nicht" do
    fremd = FileProxy.create(actor: @hans, title: "Stadtwerke", item_type: :organization, content: "")
    ein  = Invoice.create!(kind: :rechnung, direction: :eingehend)
    aus  = Invoice.create!(kind: :rechnung, direction: :ausgehend)

    post "/invoices/#{ein.id}/link", params: { field: "issuer", value: fremd.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal fremd.uuid, ein.reload.issuer_uuid

    post "/invoices/#{aus.id}/link", params: { field: "issuer", value: fremd.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_nil aus.reload.issuer_uuid, "ausgehend: nur issuer:true-Firmen erlaubt"
  end

  test "Listen-Blade bietet die manuelle Eingangsrechnung an" do
    get "/invoices/list_card"
    assert_response :success
    assert_includes @response.body, "Eingangsrechnung"
    assert_includes @response.body, "direction=eingehend"
  end

  test "Liste filtert nach Richtung" do
    Invoice.create!(kind: :rechnung, direction: :eingehend, number: "EIN-1")
    Invoice.create!(kind: :rechnung, direction: :ausgehend, number: "AUS-1")
    get "/invoices/list_card", params: { direction: "eingehend" }
    assert_response :success
    assert_includes @response.body, "EIN-1"
    refute_includes @response.body, "AUS-1"
  end

  # ── #787: Papierkorb ─────────────────────────────────────────────────────
  test "destroy/restore/trash: Soft-Delete-Zyklus" do
    invoice = Invoice.create!(kind: :rechnung, number: "2026-099")
    delete "/invoices/#{invoice.id}", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert invoice.reload.discarded?
    refute Invoice.exists?(invoice.id)

    get "/invoices/trash"
    assert_response :success
    assert_includes @response.body, "2026-099"

    post "/invoices/#{invoice.id}/restore", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert Invoice.exists?(invoice.id)
  end
end
