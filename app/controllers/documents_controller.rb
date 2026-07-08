# #532 Phase 2 (Hans, 2026-06-07): Theme-Werkbank — Beispiel-Dokumente durch das
# Print-Theme rendern (Browser-Vorschau + echtes PDF via Headless-Chrome), damit
# wir das Theme iterativ an Hans' verbalem Feedback abstimmen können.
class DocumentsController < ApplicationController
  include KnowledgeStackHelpers

  # #532: bei Status final sind Feld-Mutationen gesperrt (nur Status-Wechsel
  # zurück auf Entwurf entsperrt wieder).
  before_action :reject_if_locked, only: [:link, :create_body_ki, :document_fields, :select_identifiers, :invoice_lines, :import_time_entries, :add_invoice_line]

  SAMPLES = { "invoice" => "Rechnung", "nda" => "NDA", "letter" => "Brief" }.freeze

  # #532 (Hans, 2026-06-08): Anzeige-Labels + welche Typen schon anlegbar sind.
  # Erstmal nur allgemeine Anschreiben (Brief); weitere Typen folgen.
  KIND_LABELS    = { "brief" => "Brief", "nda" => "NDA",
                     "rechnung" => "Rechnung", "angebot" => "Angebot",
                     "lastschrift" => "SEPA-Lastschriftmandat" }.freeze   # #786
  CREATABLE_KINDS = %w[brief nda rechnung lastschrift].freeze   # #786

  # #532: /documents ist eine Blade-Stack-Seite. Initiales Card ist die
  # Dokumentenliste; ?stack= kann document:<id>-Detailblades anhängen.
  def index
    if params[:stack].blank?
      params[:stack] = "list:documents"
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # Listen-Blade als Fragment (Sidebar/Stack-Append/Cross-Page-Restore).
  def list_card
    render partial: "documents/list_blade_card", layout: false
  end

  # Detail-Blade eines Dokuments.
  def card
    @document = Document.visible_to(current_actor).find(params[:id])
    render partial: "documents/blade_card", layout: false, locals: { document: @document }
  end

  # Neues Dokument anlegen — Vordialog wählt den Typ; vorerst nur Brief.
  def create
    kind = params[:kind].to_s
    unless CREATABLE_KINDS.include?(kind)
      redirect_to documents_path, alert: "Dieser Dokumenttyp kann noch nicht angelegt werden."
      return
    end
    # #541: Rechnungsnummer ist Aussteller-spezifisch → erst beim Setzen des
    # Ausstellers vergeben (siehe #link), nicht schon beim Anlegen.
    doc = Document.create!(kind: kind, status: :entwurf,
                           creator: current_actor, document_date: Date.current)
    # #871 (Hans): Neues Dokument an den AKTUELLEN Stack anhängen (wie
    # Aufgabe/Wartepunkt/KI) statt per Redirect einen neuen Stack aufzubauen.
    # `blade_stack_container` existiert nur auf Stack-Seiten; sonst ist der
    # Stream ein No-Op und der HTML-Fallback (Redirect) greift.
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("blade_stack_container",
          partial: "documents/blade_card", locals: { document: doc })
      end
      format.html { redirect_to documents_path(stack: "list:documents,document:#{doc.id}"), status: :see_other }
    end
  end

  # Skalare Meta-Felder (Betreff/Datum/Status/Anrede/Nummer) speichern.
  def update
    @document = Document.visible_to(current_actor).find(params[:id])
    was_locked = @document.locked?
    apply_document_params!(@document)
    # #556: wechselt der Sperrzustand (final↔entwurf), den ganzen Editor-
    # Bereich austauschen, sonst nur den Felder-Block (granularer Auto-Save).
    @lock_changed = @document.locked? != was_locked
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}") }
    end
  end

  # #532 (Hans, 2026-06-08): ein neues Text-KI anlegen und gleich als Body
  # verknüpfen. Titel-Schema: "Brief - YYYY-MM-DD [Empfänger] [Betreff]".
  def create_body_ki
    @document = Document.visible_to(current_actor).find(params[:id])
    date  = (@document.document_date || Date.current).strftime("%Y-%m-%d")
    parts = [@document.kind.capitalize, "-", date,
             @document.recipient&.title, @document.subject].compact_blank
    # #766 (Hans): Vorlagentext kommt aus einer Dokument-Vorlage in den DATEN
    # (Notiz-KI mit Tag "vorlage:<kind>"), NICHT aus dem Code — der Code wird
    # ggf. veröffentlicht, der Vorlagentext (z.B. NDA-Klauseln) bleibt privat.
    ki = FileProxy.create(actor: current_actor, title: parts.join(" ").squish,
                          item_type: :note, content: document_template_body(@document.kind))
    @document.update!(body_ki_uuid: ki.uuid)
    @field = "body"
    respond_to do |format|
      format.turbo_stream { render :link }
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  # #532: freie Key-Value-Felder am Dokument (Informationsblock) — Upsert wie
  # der Identifier-Editor (stabile ids).
  def document_fields
    @document = Document.visible_to(current_actor).find(params[:id])
    seen = []
    Array(params[:fields]).each_with_index do |row, i|
      row   = row.respond_to?(:permit) ? row.permit(:id, :label, :value).to_h : row.to_h
      label = row["label"].to_s.strip
      value = row["value"].to_s.strip
      next if label.empty? || value.empty?
      rec = row["id"].present? ? @document.document_fields.find_by(id: row["id"]) : nil
      rec ||= @document.document_fields.new
      rec.assign_attributes(label: label, value: value, position: i)
      rec.save!
      seen << rec.id
    end
    @document.document_fields.where.not(id: seen).destroy_all
    @document.reload
    respond_to do |format|
      format.turbo_stream { render :infofields }
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  # #541 (Hans, 2026-06-08): Rechnungspositionen (invoice_lines) upserten —
  # gleiches stabile-id-Upsert wie document_fields. Dezimal-Eingaben dürfen
  # Komma ODER Punkt sein (deutsche Eingabe).
  def invoice_lines
    @document = Document.visible_to(current_actor).find(params[:id])
    seen = []
    Array(params[:lines]).each_with_index do |row, i|
      row  = row.respond_to?(:permit) ? row.permit(:id, :description, :quantity, :unit, :unit_price, :tax_rate).to_h : row.to_h
      desc = row["description"].to_s.strip
      qty  = decimal_param(row["quantity"])
      price = decimal_param(row["unit_price"])
      # Komplett leere Zeile überspringen.
      next if desc.empty? && qty.zero? && price.zero?
      rec = row["id"].present? ? @document.invoice_lines.find_by(id: row["id"]) : nil
      rec ||= @document.invoice_lines.new
      rec.assign_attributes(description: desc, quantity: qty, unit: row["unit"].to_s.strip,
                            unit_price: price, tax_rate: decimal_param(row["tax_rate"], default: 19), position: i)
      rec.save!
      seen << rec.id
    end
    @document.invoice_lines.where.not(id: seen).destroy_all
    @document.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  # #541 (Hans, 2026-06-09): eine neue, leere Position anlegen (wird danach im
  # Detail-Blade befüllt + bekommt ggf. Zeiten zugeordnet).
  def add_invoice_line
    @document = Document.visible_to(current_actor).find(params[:id])
    pos = @document.invoice_lines.maximum(:position).to_i + 1
    @document.invoice_lines.create!(description: "", quantity: 0, unit_price: 0,
                                    tax_rate: (@document.vat_exempt? ? 0 : 19), position: pos)
    @document.reload
    respond_to do |format|
      format.turbo_stream { render :invoice_lines }
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  # #541 (Hans, 2026-06-08): ausgewählte abrechenbare Zeitbuchungen des Projekts
  # als Rechnungspositionen übernehmen (eine Position je Buchung, Menge = Stunden
  # × Stundensatz) und die Buchungen dieser Rechnung zuordnen — so wird keine
  # Zeit doppelt abgerechnet.
  def import_time_entries
    @document = Document.visible_to(current_actor).find(params[:id])
    rate = decimal_param(params[:rate])
    pos  = @document.invoice_lines.maximum(:position).to_i
    if @document.topic
      entries = TimeEntry.for_topic(@document.topic).invoiceable
                         .where(id: Array(params[:time_entry_ids]))
      entries.each do |te|
        line = @document.invoice_lines.create!(
          description: te.bill_label, quantity: te.hours, unit: "Std",
          unit_price: rate, tax_rate: (@document.vat_exempt? ? 0 : 19), position: pos += 1)
        te.update!(invoice_line: line)
      end
    end
    @document.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  # #532: welche ID-Felder (#544) des Empfängers im Dokument erscheinen.
  def select_identifiers
    @document = Document.visible_to(current_actor).find(params[:id])
    ids       = Array(params[:identifier_ids]).map(&:to_i).reject(&:zero?)
    candidate = @document.identifier_candidates.map(&:id)
    @document.update!(shown_identifier_ids: ids & candidate)
    respond_to do |format|
      format.turbo_stream { render :infofields }
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  # #532: Picker-Vorschläge (entity-picker, dieselben wie Aufgaben/KIs).
  def suggest_links
    q = params[:q].to_s.strip.downcase
    items =
      case params[:kind]
      when "issuer"    then ki_suggest(KnowledgeItem.issuers, q)
      when "recipient" then ki_suggest(KnowledgeItem.persons_and_orgs, q)
      when "body"      then ki_suggest(KnowledgeItem.where(item_type: %i[note abstract doc synthesis]), q)
      when "topic"
        scope = Topic.all
        scope = scope.where("LOWER(name) LIKE ?", "%#{q}%") if q.present?
        scope.order(Arel.sql("LOWER(name)")).limit(10).map { |t| { slug: t.slug, label: t.name } }
      else []
      end
    render json: { items: items }
  end

  # #532: eine Verknüpfung setzen oder lösen (value leer = lösen). Antwortet
  # mit Turbo-Stream, der den Chip der jeweiligen Verknüpfung ersetzt.
  def link
    @document = Document.visible_to(current_actor).find(params[:id])
    @field    = params[:field].to_s
    value     = params[:value].to_s.strip
    case @field
    when "issuer"
      @document.update!(issuer_uuid: resolve_ki(value, KnowledgeItem.issuers))
      # #541: Aussteller-spezifische Rechnungsnummer vergeben, sobald der
      # Aussteller feststeht und noch keine Nummer existiert.
      if @document.rechnung? && @document.number.blank? && @document.issuer_uuid.present?
        @document.update!(number: Document.next_invoice_number(@document.issuer_uuid))
      end
    when "recipient" then @document.update!(recipient_uuid: resolve_ki(value, KnowledgeItem.persons_and_orgs))
    when "body"      then @document.update!(body_ki_uuid:   resolve_ki(value, KnowledgeItem.all))
    when "topic"     then @document.update!(topic_id:       (Topic.find_by(slug: value)&.id if value.present?))
    else return head(:unprocessable_content)
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  def preview
    @sample = SAMPLES.key?(params[:sample]) ? params[:sample] : "invoice"
    load_issuers
    render layout: false   # selbst-enthaltene Seite (siehe preview.html.erb)
  end

  def pdf
    sample = SAMPLES.key?(params[:sample]) ? params[:sample] : "invoice"
    load_issuers
    html = render_to_string(template: "documents/document", layout: false,
                            locals: { sample: sample })
    send_data DocumentPdf.render(html),
              type: "application/pdf", disposition: "inline",
              filename: "#{sample}-vorschau.pdf"
  rescue DocumentPdf::Error => e
    render plain: "PDF-Render fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  # #532 (2026-06-08): einen echten Document-Record datengetrieben rendern
  # (DIN-5008-Theme). @issuer speist den gemeinsamen Briefkopf.
  def show
    @document = Document.visible_to(current_actor).find(params[:id])
    @issuer   = @document.issuer
    render layout: false
  end

  def show_pdf
    @document = Document.visible_to(current_actor).find(params[:id])
    @issuer   = @document.issuer
    html = render_to_string(template: "documents/rendered", layout: false)
    send_data document_pdf_bytes(@document, html),
              type: "application/pdf", disposition: "inline",
              filename: "#{@document.kind}-#{@document.id}.pdf"
  rescue DocumentPdf::Error => e
    render plain: "PDF-Render fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  # #541 (Hans, 2026-06-09): ZUGFeRD-PDF/A-3 (sichtbare Rechnung + eingebettete
  # EN16931-XML) bzw. reine XRechnung-XML.
  def zugferd_pdf
    @document = Document.visible_to(current_actor).find(params[:id])
    @issuer   = @document.issuer
    visible   = DocumentPdf.render(render_to_string(template: "documents/rendered", layout: false))
    send_data ZugferdGenerator.zugferd_pdf(@document, visible),
              type: "application/pdf", disposition: "inline",
              filename: "rechnung-#{@document.number.presence || @document.id}.pdf"
  rescue ZugferdGenerator::Error, DocumentPdf::Error => e
    render plain: "ZUGFeRD-Erzeugung fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  def xrechnung_xml
    @document = Document.visible_to(current_actor).find(params[:id])
    send_data ZugferdGenerator.xml(@document),
              type: "application/xml", disposition: "attachment",
              filename: "rechnung-#{@document.number.presence || @document.id}.xml"
  rescue ZugferdGenerator::Error => e
    render plain: "XRechnung-Erzeugung fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  # #547: AES-signiertes PDF — rendert mit sichtbarem Signatur-Vermerk und
  # legt eine kryptografische PAdES-Signatur (pyHanko) darüber.
  def signed_pdf
    @document = Document.visible_to(current_actor).find(params[:id])
    @issuer   = @document.issuer
    @signed   = true
    @signature_image = current_actor.signature_image  # #547: sichtbares Bild
    html   = render_to_string(template: "documents/rendered", layout: false)
    pdf    = document_pdf_bytes(@document, html)
    signed = DocumentSigner.sign(pdf, reason: "Elektronisch signiert: #{@issuer&.title}")
    send_data signed, type: "application/pdf", disposition: "inline",
              filename: "#{@document.kind}-#{@document.id}-signiert.pdf"
  rescue DocumentPdf::Error, DocumentSigner::Error => e
    render plain: "Signieren fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  # #532 (Hans, 2026-06-08): das aktuelle (signierte) PDF dauerhaft als Stand
  # festschreiben — nur bei Status final. Liste der Stände im Detail-Blade.
  def archive_pdf
    @document = Document.visible_to(current_actor).find(params[:id])
    unless @document.final?
      redirect_to documents_path(stack: "list:documents,document:#{@document.id}"),
                  alert: "Nur finale Dokumente lassen sich festschreiben.", status: :see_other and return
    end
    @issuer          = @document.issuer
    @signed          = true
    @signature_image = current_actor.signature_image
    html   = render_to_string(template: "documents/rendered", layout: false)
    pdf    = DocumentPdf.render(html)
    signed = DocumentSigner.available?
    pdf    = DocumentSigner.sign(pdf, reason: "Finaler Stand: #{@issuer&.title}") if signed
    @document.document_artifacts.create!(pdf: pdf, signed: signed, creator: current_actor)
    respond_to do |format|
      format.turbo_stream { render :archived }
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  rescue DocumentPdf::Error, DocumentSigner::Error => e
    redirect_to documents_path(stack: "list:documents,document:#{@document.id}"),
                alert: "Festschreiben fehlgeschlagen: #{e.message}", status: :see_other
  end

  # Einen festgeschriebenen Stand ausliefern.
  def artifact
    @document = Document.visible_to(current_actor).find(params[:id])
    art = @document.document_artifacts.find(params[:artifact_id])
    send_data art.pdf, type: "application/pdf", disposition: "inline",
              filename: "#{@document.kind}-#{@document.id}-#{art.created_at.strftime('%Y%m%d-%H%M%S')}.pdf"
  end

  # #536: Portal-Freigabe eines festgeschriebenen Stands togglen. Beim
  # Freigeben bekommen die Portal-Zugänge des Projekts einen Mail-Ping.
  def toggle_artifact_share
    @document = Document.visible_to(current_actor).find(params[:id])
    art = @document.document_artifacts.find(params[:artifact_id])
    art.update!(shared_with_client: !art.shared_with_client)
    if art.shared_with_client && @document.topic
      PortalNotifier.content_shared(@document.topic,
        what: "Ein neues Dokument wurde für Sie bereitgestellt: #{@document.display_name.presence || 'Dokument'}.")
    end
    render turbo_stream: turbo_stream.replace("document_artifacts_#{@document.id}",
      partial: "documents/artifacts", locals: { document: @document })
  end

  # #787 (Hans): Dokument in den Papierkorb legen (Soft-Delete). Karte + Listen-
  # Row raus, Toast mit Undo (restore). Artefakte/Felder/Positionen bleiben am
  # Datensatz hängen → restore stellt alles wieder her.
  def destroy
    @document = Document.visible_to(current_actor).find(params[:id])
    @document.discard!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("stack_card_document:#{@document.id}"),
          turbo_stream.remove("document_row_#{@document.id}"),
          helpers.toast_stream(message: t("documents.trash.deleted"),
                               undo_url: restore_document_path(@document))
        ]
      end
      format.html { redirect_to documents_path, notice: t("documents.trash.deleted"), status: :see_other }
    end
  end

  # #787: aus dem Papierkorb zurückholen.
  def restore
    @document = Document.with_discarded.visible_to(current_actor).find(params[:id])
    @document.undiscard!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: helpers.toast_stream(message: t("documents.trash.restored")) }
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  # #787: Papierkorb — gelöschte Dokumente (restore-fähig).
  def trash
    @discarded = Document.discarded.visible_to(current_actor).recent.limit(100)
  end

  # #787: einen finalen PDF-Stand (Artefakt) hart löschen (re-archivierbar).
  def destroy_artifact
    @document = Document.visible_to(current_actor).find(params[:id])
    @document.document_artifacts.find(params[:artifact_id]).destroy!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("document_artifacts_#{@document.id}",
            partial: "documents/artifacts", locals: { document: @document }),
          helpers.toast_stream(message: t("documents.trash.artifact_deleted"))
        ]
      end
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"), status: :see_other }
    end
  end

  private

  # #766 (Hans): Vorlagentext eines Dokumenttyps aus den DATEN holen — eine
  # Notiz-KI mit Tag "vorlage:<kind>" (z.B. "vorlage:nda"). Existiert keine,
  # bleibt der Body leer. Bewusst NICHT im Code, da dieser veröffentlicht wird.
  def document_template_body(kind)
    KnowledgeItem.where(item_type: "note")
                 .where("? = ANY(tags)", "vorlage:#{kind}")
                 .order(:created_at).first&.body.to_s
  end

  # #562 (Hans): NDA als mehrseitiges Dokument mit Rändern + Fußzeile (Seitenzahl
  # + Dokument-ID) auf jeder Seite (Ferrum/CDP). Alle anderen Typen: DIN-Geometrie
  # via @page/CSS, einfacher CLI-Render.
  def document_pdf_bytes(document, html)
    if document.nda?
      DocumentPdf.render_paged(html, footer_html: nda_footer_html(document))
    else
      # #786 (Hans): lastschrift nutzt jetzt die DIN-Geometrie (Anschriftfeld
      # fürs Kuvert) → wie Brief/Rechnung über den CLI-DIN-Render. Der
      # .din-body hat 20mm unteren Rand; das kurze Formular endet weit davor.
      DocumentPdf.render(html)
    end
  end

  # Chrome-Footer-Template: links die Dokument-ID, rechts „Seite X von Y".
  # font-size MUSS inline stehen (Chrome resettet sonst auf 0); die Klassen
  # pageNumber/totalPages füllt Chrome beim Druck.
  def nda_footer_html(document)
    id = ERB::Util.html_escape(document.pdf_doc_id)
    %(<div style="font-size:7pt; width:100%; padding:0 20mm 0 25mm; color:#555; ) +
      %(font-family:Helvetica,Arial,sans-serif; display:flex; justify-content:space-between;">) +
      %(<span>#{id}</span>) +
      %(<span>Seite <span class="pageNumber"></span> von <span class="totalPages"></span></span></div>)
  end

  # #541: Dezimal-Eingabe robust parsen — Komma oder Punkt, leer = default.
  def decimal_param(raw, default: 0)
    s = raw.to_s.strip.tr(",", ".")
    return BigDecimal(default.to_s) if s.empty?
    BigDecimal(s)
  rescue ArgumentError
    BigDecimal(default.to_s)
  end

  # #532: bei Status final sind nur Status-Wechsel erlaubt (Entsperren).
  def reject_if_locked
    @document = Document.visible_to(current_actor).find(params[:id])
    return unless @document.locked?
    respond_to do |format|
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@document.id}"),
                                alert: "Dokument ist final (gesperrt).", status: :see_other }
      format.any  { head :forbidden }
    end
  end

  # #532: Aussteller-KIs für den Briefkopf. @issuer = gewählter (Param) oder
  # erster markierter Aussteller; @issuers für die Werkbank-Auswahl.
  def load_issuers
    @issuers = KnowledgeItem.issuers.order(Arel.sql("LOWER(title) ASC"))
    @issuer  = (@issuers.find_by(uuid: params[:issuer]) if params[:issuer].present?) ||
               @issuers.first
  end

  # Wendet die skalaren Meta-Felder an. Verknüpfungen laufen über #link
  # (entity-picker). Bei Status final ist nur der Status selbst änderbar.
  def apply_document_params!(doc)
    attrs = {}
    attrs[:status] = params[:status] if params.key?(:status) && Document.statuses.key?(params[:status])
    unless doc.locked?
      attrs[:subject]       = params[:subject]                if params.key?(:subject)
      attrs[:salutation]    = params[:salutation]             if params.key?(:salutation)
      attrs[:number]        = params[:number]                 if params.key?(:number)
      attrs[:document_date] = params[:document_date].presence if params.key?(:document_date)
      attrs[:service_start] = params[:service_start].presence if params.key?(:service_start)  # #541 Leistungszeitraum
      attrs[:service_end]   = params[:service_end].presence   if params.key?(:service_end)
      attrs[:your_ref]      = params[:your_ref]               if params.key?(:your_ref)
      attrs[:our_ref]       = params[:our_ref]                if params.key?(:our_ref)
      # #694: gewählte Empfänger-Postadresse — nur zulassen, wenn sie zum
      # aktuellen Empfänger gehört; leer/ungültig = automatisch (nil).
      if params.key?(:recipient_address_id)
        rid = params[:recipient_address_id].presence
        valid = rid && doc.recipient&.postal_addresses&.exists?(id: rid)
        attrs[:recipient_address_id] = valid ? rid : nil
      end
      # #786 Inkr.2: gewählte Schuldner-Bankverbindung — nur zulassen, wenn sie
      # zum aktuellen Aussteller gehört; leer/ungültig = automatisch (nil).
      if params.key?(:debtor_bank_account_id)
        bid = params[:debtor_bank_account_id].presence
        valid = bid && doc.issuer&.bank_accounts&.exists?(id: bid)
        attrs[:debtor_bank_account_id] = valid ? bid : nil
      end
    end
    doc.update!(attrs) if attrs.any?
  end

  # #532: Picker-Vorschläge für KI-Verknüpfungen (uuid als slug).
  def ki_suggest(scope, q)
    scope = scope.where("LOWER(title) LIKE ?", "%#{q}%") if q.present?
    scope.order(Arel.sql("LOWER(title)")).limit(10).map { |k| { slug: k.uuid, label: k.title } }
  end

  # value ist die vom Picker gepostete uuid; nil/leer = lösen. Validiert,
  # dass die uuid im erlaubten Scope liegt.
  def resolve_ki(uuid, scope)
    return nil if uuid.blank?
    scope.find_by(uuid: uuid)&.uuid
  end

  def controller_resource_type = "Task"  # weicher Gate (V1)
end
