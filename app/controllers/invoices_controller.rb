# #926 (Hans, 2026-07-09): Rechnung/Angebot als eigene Entität — vorher ein
# kind des Sammel-Modells Document. Das gemeinsame Erstellungs-Verfahren
# (Blade, Auto-Save, Picker, Felder, PDF/Signatur/Festschreiben, Papierkorb)
# kommt aus PrintableResource; hier lebt nur das Rechnungs-Spezifische:
# Positionen (invoice_lines), Zeiten-Import, Nummernkreis, ZUGFeRD/XRechnung.
class InvoicesController < ApplicationController
  include KnowledgeStackHelpers
  include PrintableResource

  # #532: bei Status final sind Feld-Mutationen gesperrt (nur Status-Wechsel
  # zurück auf Entwurf entsperrt wieder).
  before_action :reject_if_locked, only: [:link, :document_fields, :select_identifiers, :invoice_lines, :import_time_entries, :add_invoice_line]

  KIND_LABELS     = { "rechnung" => "Rechnung", "angebot" => "Angebot" }.freeze
  CREATABLE_KINDS = %w[rechnung angebot].freeze

  # /invoices ist eine Blade-Stack-Seite. Initiales Card ist die
  # Rechnungsliste; ?stack= kann invoice:<id>-Detailblades anhängen.
  def index
    if params[:stack].blank?
      params[:stack] = "list:invoices"
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # Listen-Blade als Fragment (Sidebar/Stack-Append/Cross-Page-Restore).
  def list_card
    render partial: "invoices/list_blade_card", layout: false
  end

  # Neue Rechnung / neues Angebot anlegen.
  def create
    kind = params[:kind].to_s
    kind = "rechnung" unless CREATABLE_KINDS.include?(kind)
    # #946: Eingangsrechnung auch manuell anlegbar (bisher nur Dokument-Import).
    # Richtung nur für Rechnungen wählbar; Angebote bleiben ausgehend.
    direction = (kind == "rechnung" && params[:direction].to_s == "eingehend") ? :eingehend : :ausgehend
    # #541: Rechnungsnummer ist Aussteller-spezifisch → erst beim Setzen des
    # Ausstellers vergeben (siehe after_link), nicht schon beim Anlegen.
    invoice = Invoice.create!(kind: kind, direction: direction, status: :entwurf,
                              creator: current_actor, document_date: Date.current)
    # #871 (Hans): an den AKTUELLEN Stack anhängen statt neuen Stack aufzubauen.
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("blade_stack_container",
          partial: "invoices/blade_card", locals: { invoice: invoice })
      end
      format.html { redirect_to invoices_path(stack: "list:invoices,invoice:#{invoice.id}"), status: :see_other }
    end
  end

  # #541 (Hans, 2026-06-08): Rechnungspositionen (invoice_lines) upserten —
  # gleiches stabile-id-Upsert wie document_fields. Dezimal-Eingaben dürfen
  # Komma ODER Punkt sein (deutsche Eingabe).
  def invoice_lines
    load_printable
    seen = []
    Array(params[:lines]).each_with_index do |row, i|
      row  = row.respond_to?(:permit) ? row.permit(:id, :description, :quantity, :unit, :unit_price, :tax_rate).to_h : row.to_h
      desc = row["description"].to_s.strip
      qty  = decimal_param(row["quantity"])
      price = decimal_param(row["unit_price"])
      # Komplett leere Zeile überspringen.
      next if desc.empty? && qty.zero? && price.zero?
      rec = row["id"].present? ? @invoice.invoice_lines.find_by(id: row["id"]) : nil
      rec ||= @invoice.invoice_lines.new
      rec.assign_attributes(description: desc, quantity: qty, unit: row["unit"].to_s.strip,
                            unit_price: price, tax_rate: decimal_param(row["tax_rate"], default: 19), position: i)
      rec.save!
      seen << rec.id
    end
    @invoice.invoice_lines.where.not(id: seen).destroy_all
    @invoice.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to printable_stack_path(@invoice), status: :see_other }
    end
  end

  # #541 (Hans, 2026-06-09): eine neue, leere Position anlegen (wird danach im
  # Detail-Blade befüllt + bekommt ggf. Zeiten zugeordnet).
  def add_invoice_line
    load_printable
    pos = @invoice.invoice_lines.maximum(:position).to_i + 1
    @invoice.invoice_lines.create!(description: "", quantity: 0, unit_price: 0,
                                   tax_rate: (@invoice.vat_exempt? ? 0 : 19), position: pos)
    @invoice.reload
    respond_to do |format|
      format.turbo_stream { render :invoice_lines }
      format.html { redirect_to printable_stack_path(@invoice), status: :see_other }
    end
  end

  # #541 (Hans, 2026-06-08): ausgewählte abrechenbare Zeitbuchungen des Projekts
  # als Rechnungspositionen übernehmen (eine Position je Buchung, Menge = Stunden
  # × Stundensatz) und die Buchungen dieser Rechnung zuordnen — so wird keine
  # Zeit doppelt abgerechnet.
  def import_time_entries
    load_printable
    return head(:unprocessable_content) if @invoice.eingehend?  # #968: keine Zeiten an fremden Belegen
    rate = decimal_param(params[:rate])
    pos  = @invoice.invoice_lines.maximum(:position).to_i
    if @invoice.topic
      entries = TimeEntry.for_topic(@invoice.topic).invoiceable
                         .where(id: Array(params[:time_entry_ids]))
      entries.each do |te|
        line = @invoice.invoice_lines.create!(
          description: te.bill_label, quantity: te.hours, unit: "Std",
          unit_price: rate, tax_rate: (@invoice.vat_exempt? ? 0 : 19), position: pos += 1)
        te.update!(invoice_line: line)
      end
    end
    @invoice.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to printable_stack_path(@invoice), status: :see_other }
    end
  end

  # #541 (Hans, 2026-06-09): ZUGFeRD-PDF/A-3 (sichtbare Rechnung + eingebettete
  # EN16931-XML) bzw. reine XRechnung-XML.
  def zugferd_pdf
    load_printable
    @issuer = @invoice.issuer
    visible = DocumentRenderer.pdf(@invoice, printable_html)
    send_data ZugferdGenerator.zugferd_pdf(@invoice, visible),
              type: "application/pdf", disposition: "inline",
              filename: "rechnung-#{@invoice.number.presence || @invoice.id}.pdf"
  rescue ZugferdGenerator::Error, DocumentPdf::Error => e
    render plain: "ZUGFeRD-Erzeugung fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  def xrechnung_xml
    load_printable
    send_data ZugferdGenerator.xml(@invoice),
              type: "application/xml", disposition: "attachment",
              filename: "rechnung-#{@invoice.number.presence || @invoice.id}.xml"
  rescue ZugferdGenerator::Error => e
    render plain: "XRechnung-Erzeugung fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  # #964 (Hans): Beleg (Original-PDF) manuell an eine EINGANGSRECHNUNG
  # hängen — bisher kamen Artefakte nur aus dem Dokument-Import. Nur
  # eingehend (ausgehende Stände entstehen ausschließlich über das
  # Festschreiben); nur PDF (die Artefakt-Schicht serviert application/pdf).
  MAX_ARTIFACT_BYTES = 25.megabytes

  def upload_artifact
    load_printable
    return head(:unprocessable_content) unless @invoice.eingehend?
    file = params[:file]
    error =
      if file.blank?                                  then t("invoices.upload.missing")
      elsif file.size > MAX_ARTIFACT_BYTES            then t("invoices.upload.too_large")
      elsif !pdf_upload?(file)                        then t("invoices.upload.not_pdf")
      end
    if error
      respond_to do |format|
        format.turbo_stream { render turbo_stream: helpers.toast_stream(message: error) }
        format.html { redirect_to printable_stack_path(@invoice), alert: error, status: :see_other }
      end
      return
    end
    @invoice.document_artifacts.create!(pdf: file.read, creator: current_actor)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("invoice_artifacts_#{@invoice.id}",
          partial: "printables/artifacts", locals: { printable: @invoice })
      end
      format.html { redirect_to printable_stack_path(@invoice), status: :see_other }
    end
  end

  private

  # PDF-Erkennung über die Magic Bytes (Content-Type ist Client-Angabe).
  def pdf_upload?(file)
    head = file.read(5)
    file.rewind
    head == "%PDF-"
  end

  def printable_model = Invoice

  def printable_stack_path(invoice)
    invoices_path(stack: "list:invoices,invoice:#{invoice.id}")
  end

  # Wendet die skalaren Meta-Felder an (Auto-Save).
  def apply_printable_params!(invoice)
    attrs = {}
    attrs[:subject]       = params[:subject]                if params.key?(:subject)
    attrs[:number]        = params[:number]                 if params.key?(:number)
    attrs[:document_date] = params[:document_date].presence if params.key?(:document_date)
    attrs[:service_start] = params[:service_start].presence if params.key?(:service_start)  # #541 Leistungszeitraum
    attrs[:service_end]   = params[:service_end].presence   if params.key?(:service_end)
    attrs[:due_date]      = params[:due_date].presence      if params.key?(:due_date)       # #934 Fälligkeit
    if params.key?(:payment_status) && Invoice.payment_statuses.key?(params[:payment_status])
      attrs[:payment_status] = params[:payment_status]      # #934 Zahlstatus
    end
    attrs[:your_ref]      = params[:your_ref]               if params.key?(:your_ref)
    attrs[:our_ref]       = params[:our_ref]                if params.key?(:our_ref)
    # #694: gewählte Empfänger-Postadresse — nur zulassen, wenn sie zum
    # aktuellen Empfänger gehört; leer/ungültig = automatisch (nil).
    if params.key?(:recipient_address_id)
      rid = params[:recipient_address_id].presence
      valid = rid && invoice.recipient&.postal_addresses&.exists?(id: rid)
      attrs[:recipient_address_id] = valid ? rid : nil
    end
    invoice.update!(attrs) if attrs.any?
  end

  def suggest_scope(kind)
    case kind
    # #946: bei Eingangsrechnungen ist der Aussteller eine FREMDE Partei —
    # der Picker schlägt dann Personen/Orgs vor statt der eigenen Firmen
    # (issuer:true). Die Richtung kommt als Query-Param aus dem Felder-Blade.
    when "issuer"    then params[:direction].to_s == "eingehend" ? KnowledgeItem.persons_and_orgs : KnowledgeItem.issuers
    when "recipient" then KnowledgeItem.persons_and_orgs
    end
  end

  # #946: Gegenstück beim Setzen der Verknüpfung (siehe suggest_scope).
  def issuer_link_scope
    @invoice.eingehend? ? KnowledgeItem.persons_and_orgs : KnowledgeItem.issuers
  end

  # #541: Aussteller-spezifische Rechnungsnummer vergeben, sobald der
  # Aussteller feststeht und noch keine Nummer existiert.
  def after_link(field)
    return unless field == "issuer"
    # #934: Nummernkreis nur für AUSGEHENDE Rechnungen — bei eingehenden
    # kommt die Nummer vom fremden Aussteller.
    if @invoice.ausgehend? && @invoice.rechnung? && @invoice.number.blank? && @invoice.issuer_uuid.present?
      @invoice.update!(number: Invoice.next_number(@invoice.issuer_uuid))
    end
  end

  def controller_resource_type = "Task"  # weicher Gate (V1)
end
