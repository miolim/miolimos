# #926 (Hans, 2026-07-09): die gemeinsamen Controller-Actions aller
# druckbaren Entitäten (Document = Anschreiben, Invoice = Rechnung/Angebot) —
# das „Verfahren der Dokumenterstellung" auf HTTP-Ebene: Detail-Blade,
# Auto-Save, Verknüpfungen (Picker), Infoblock-Felder, Render/PDF/Signatur,
# Festschreiben (Artefakte), Portal-Freigabe, Papierkorb.
#
# Der Controller liefert die typ-spezifischen Teile als Hooks:
#   printable_model            — Document / Invoice
#   printable_stack_path(p)    — Redirect-Ziel (Blade-Stack-URL)
#   apply_printable_params!(p) — skalare Auto-Save-Felder
#   suggest_scope(kind)        — Picker-Scopes (nil = kind unbekannt)
#   after_link(field)          — z.B. Rechnungsnummer nach Aussteller-Wahl
# Templates (show/rendered + *.turbo_stream) liegen im View-Verzeichnis des
# Controllers; geteilte Partials unter app/views/printables/.
module PrintableResource
  extend ActiveSupport::Concern

  # Detail-Blade der Entität.
  def card
    load_printable
    render partial: "#{controller_name}/blade_card", layout: false,
           locals: { printable_local_name => @printable }
  end

  # Skalare Meta-Felder speichern (Auto-Save aus dem Blade).
  def update
    load_printable
    was_locked = @printable.locked?
    @printable.update!(status: params[:status]) if params.key?(:status) && printable_model.statuses.key?(params[:status])
    apply_printable_params!(@printable) unless @printable.locked?
    # #556: wechselt der Sperrzustand (final↔entwurf), den ganzen Editor-
    # Bereich austauschen, sonst nur den Felder-Block (granularer Auto-Save).
    @lock_changed = @printable.locked? != was_locked
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to printable_stack_path(@printable) }
    end
  end

  # #532: freie Key-Value-Felder (Informationsblock) — Upsert mit stabilen ids.
  def document_fields
    load_printable
    seen = []
    Array(params[:fields]).each_with_index do |row, i|
      row   = row.respond_to?(:permit) ? row.permit(:id, :label, :value).to_h : row.to_h
      label = row["label"].to_s.strip
      value = row["value"].to_s.strip
      next if label.empty? || value.empty?
      rec = row["id"].present? ? @printable.document_fields.find_by(id: row["id"]) : nil
      rec ||= @printable.document_fields.new
      rec.assign_attributes(label: label, value: value, position: i)
      rec.save!
      seen << rec.id
    end
    @printable.document_fields.where.not(id: seen).destroy_all
    @printable.reload
    respond_to do |format|
      format.turbo_stream { render :infofields }
      format.html { redirect_to printable_stack_path(@printable), status: :see_other }
    end
  end

  # #532: welche ID-Felder (#544) des Empfängers im Dokument erscheinen.
  def select_identifiers
    load_printable
    ids       = Array(params[:identifier_ids]).map(&:to_i).reject(&:zero?)
    candidate = @printable.identifier_candidates.map(&:id)
    @printable.update!(shown_identifier_ids: ids & candidate)
    respond_to do |format|
      format.turbo_stream { render :infofields }
      format.html { redirect_to printable_stack_path(@printable), status: :see_other }
    end
  end

  # #532: Picker-Vorschläge (entity-picker, dieselben wie Aufgaben/KIs).
  def suggest_links
    q     = params[:q].to_s.strip.downcase
    scope = suggest_scope(params[:kind].to_s)
    items =
      if params[:kind].to_s == "topic"
        s = Topic.all
        s = s.where("LOWER(name) LIKE ?", "%#{q}%") if q.present?
        s.order(Arel.sql("LOWER(name)")).limit(10).map { |t| { slug: t.slug, label: t.name } }
      elsif scope
        ki_suggest(scope, q)
      else
        []
      end
    render json: { items: items }
  end

  # #532: eine Verknüpfung setzen oder lösen (value leer = lösen). Antwortet
  # mit Turbo-Stream, der den Chip der jeweiligen Verknüpfung ersetzt.
  def link
    load_printable
    @field = params[:field].to_s
    value  = params[:value].to_s.strip
    case @field
    when "issuer"    then @printable.update!(issuer_uuid:    resolve_ki(value, issuer_link_scope))
    when "recipient" then @printable.update!(recipient_uuid: resolve_ki(value, KnowledgeItem.persons_and_orgs))
    when "topic"     then @printable.update!(topic_id:       (Topic.find_by(slug: value)&.id if value.present?))
    else
      return head(:unprocessable_content) unless link_extra_field!(@field, value)
    end
    after_link(@field)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to printable_stack_path(@printable), status: :see_other }
    end
  end

  # #532 (2026-06-08): die Entität datengetrieben rendern (DIN-5008-Theme),
  # als selbst-enthaltene Seite. @issuer speist den gemeinsamen Briefkopf.
  def show
    load_printable
    @issuer = @printable.issuer
    render layout: false
  end

  def show_pdf
    load_printable
    @issuer = @printable.issuer
    send_data DocumentRenderer.pdf(@printable, printable_html),
              type: "application/pdf", disposition: "inline",
              filename: "#{printable_basename}.pdf"
  rescue DocumentPdf::Error => e
    render plain: "PDF-Render fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  # #547: AES-signiertes PDF — rendert mit sichtbarem Signatur-Vermerk und
  # legt eine kryptografische PAdES-Signatur (pyHanko) darüber.
  def signed_pdf
    load_printable
    @issuer          = @printable.issuer
    @signed          = true
    @signature_image = current_actor.signature_image
    signed = DocumentRenderer.signed_pdf(@printable, printable_html,
                                         reason: "Elektronisch signiert: #{@issuer&.title}")
    send_data signed, type: "application/pdf", disposition: "inline",
              filename: "#{printable_basename}-signiert.pdf"
  rescue DocumentPdf::Error, DocumentSigner::Error => e
    render plain: "Signieren fehlgeschlagen: #{e.message}", status: :unprocessable_content
  end

  # #532 (Hans, 2026-06-08): das aktuelle (signierte) PDF dauerhaft als Stand
  # festschreiben — nur bei Status final. Liste der Stände im Detail-Blade.
  def archive_pdf
    load_printable
    unless @printable.final?
      redirect_to printable_stack_path(@printable),
                  alert: "Nur finale Dokumente lassen sich festschreiben.", status: :see_other and return
    end
    @issuer          = @printable.issuer
    @signed          = true
    @signature_image = current_actor.signature_image
    DocumentRenderer.archive!(@printable, printable_html, creator: current_actor)
    respond_to do |format|
      format.turbo_stream { render :archived }
      format.html { redirect_to printable_stack_path(@printable), status: :see_other }
    end
  rescue DocumentPdf::Error, DocumentSigner::Error => e
    redirect_to printable_stack_path(@printable),
                alert: "Festschreiben fehlgeschlagen: #{e.message}", status: :see_other
  end

  # Einen festgeschriebenen Stand ausliefern.
  def artifact
    load_printable
    art = @printable.document_artifacts.find(params[:artifact_id])
    send_data art.pdf, type: "application/pdf", disposition: "inline",
              filename: "#{printable_basename}-#{art.created_at.strftime('%Y%m%d-%H%M%S')}.pdf"
  end

  # #536: Portal-Freigabe eines festgeschriebenen Stands togglen. Beim
  # Freigeben bekommen die Portal-Zugänge des Projekts einen Mail-Ping.
  def toggle_artifact_share
    load_printable
    art = @printable.document_artifacts.find(params[:artifact_id])
    art.update!(shared_with_client: !art.shared_with_client)
    if art.shared_with_client && @printable.topic
      PortalNotifier.content_shared(@printable.topic,
        what: "Ein neues Dokument wurde für Sie bereitgestellt: #{@printable.display_name.presence || 'Dokument'}.")
    end
    render turbo_stream: turbo_stream.replace("#{printable_param_key}_artifacts_#{@printable.id}",
      partial: "printables/artifacts", locals: { printable: @printable })
  end

  # #995: Frankieren — Internetmarke ins Anschriftfeld. dummy=1 erzeugt eine
  # MUSTER-Marke (Layout-Test ohne Portokasse); sonst Kauf über die
  # Zugangsdaten des aktuellen Nutzers (Einstellungen → Frankierung).
  def franking
    load_printable
    return franking_error(t("printables.franking.not_frankable")) unless @printable.frankable?
    product = Internetmarke.product(params[:product])
    return franking_error(t("printables.franking.unknown_product")) unless product

    if params[:dummy].present?
      attrs = { dummy: true, image: Internetmarke::DummyStamp.data_uri(product) }
    else
      credential = current_actor.internetmarke_credential
      return franking_error(t("printables.franking.no_credentials")) unless credential
      bought = Internetmarke::Client.new(credential)
                 .buy_png(product_code: product[:code], price_cents: product[:cents])
      attrs = { dummy: false, voucher_id: bought[:voucher_id],
                wallet_balance_cents: bought[:wallet_balance],
                image: "data:image/png;base64,#{Base64.strict_encode64(bought[:png])}" }
    end
    @printable.postage_voucher&.destroy!
    @printable.create_postage_voucher!(attrs.merge(
      product_code: product[:code], product_label: product[:label],
      price_cents: product[:cents], creator: current_actor))
    replace_franking
  rescue Internetmarke::Client::Error => e
    franking_error(t("printables.franking.buy_failed", error: e.message))
  end

  # #995: Frankierung entfernen (echte Marke: Porto verfällt — confirm im View).
  def destroy_franking
    load_printable
    @printable.postage_voucher&.destroy!
    replace_franking
  end

  # #787: einen finalen PDF-Stand (Artefakt) hart löschen (re-archivierbar).
  def destroy_artifact
    load_printable
    @printable.document_artifacts.find(params[:artifact_id]).destroy!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("#{printable_param_key}_artifacts_#{@printable.id}",
            partial: "printables/artifacts", locals: { printable: @printable }),
          helpers.toast_stream(message: t("#{trash_i18n_scope}.artifact_deleted"))
        ]
      end
      format.html { redirect_to printable_stack_path(@printable), status: :see_other }
    end
  end

  # #787 (Hans): in den Papierkorb legen (Soft-Delete). Karte + Listen-Row
  # raus, Toast mit Undo (restore). Artefakte/Felder bleiben am Datensatz
  # hängen → restore stellt alles wieder her.
  def destroy
    load_printable
    @printable.discard!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("stack_card_#{printable_param_key}:#{@printable.id}"),
          turbo_stream.remove("#{printable_param_key}_row_#{@printable.id}"),
          helpers.toast_stream(message: t("#{trash_i18n_scope}.deleted"),
                               undo_url: url_for([:restore, @printable]))
        ]
      end
      format.html { redirect_to url_for(printable_model), notice: t("#{trash_i18n_scope}.deleted"), status: :see_other }
    end
  end

  # #787: aus dem Papierkorb zurückholen.
  def restore
    @printable = printable_model.with_discarded.visible_to(current_actor).find(params[:id])
    expose_printable_ivar
    @printable.undiscard!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: helpers.toast_stream(message: t("#{trash_i18n_scope}.restored")) }
      format.html { redirect_to printable_stack_path(@printable), status: :see_other }
    end
  end

  # #787: Papierkorb — gelöschte Einträge (restore-fähig).
  def trash
    @discarded = printable_model.discarded.visible_to(current_actor).recent.limit(100)
  end

  private

  # #995: Frankierungs-Block im Blade live austauschen (beide Verben).
  def replace_franking
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("#{printable_param_key}_franking_#{@printable.id}",
          partial: "printables/franking", locals: { printable: @printable })
      end
      format.html { redirect_to printable_stack_path(@printable), status: :see_other }
    end
  end

  def franking_error(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: helpers.toast_stream(message: message) }
      format.html { redirect_to printable_stack_path(@printable), alert: message, status: :see_other }
    end
  end

  def printable_model = raise(NotImplementedError)
  def printable_param_key   = printable_model.model_name.param_key
  def printable_local_name  = printable_param_key.to_sym

  # Zusätzliche link-Felder des Typs (z.B. body beim Anschreiben).
  # true = behandelt, false = unbekanntes Feld (422).
  def link_extra_field!(_field, _value) = false
  def after_link(_field) = nil

  # #946: erlaubter Scope für die Aussteller-Verknüpfung. Default: eigene
  # Firmen (issuer:true); Invoices weiten bei Eingangsrechnungen auf
  # Personen/Orgs auf (fremder Aussteller).
  def issuer_link_scope = KnowledgeItem.issuers

  def trash_i18n_scope = "#{controller_name}.trash"

  def load_printable
    @printable = printable_model.visible_to(current_actor).find(params[:id])
    expose_printable_ivar
  end

  # Views/Turbo-Templates des Controllers arbeiten mit der sprechenden
  # ivar (@document/@invoice) — beide zeigen auf dasselbe Objekt.
  def expose_printable_ivar
    instance_variable_set("@#{printable_param_key}", @printable)
  end

  # Selbst-enthaltenes Render-HTML (Theme inline) für PDF/Signatur/Archiv.
  def printable_html
    render_to_string(template: "#{controller_name}/rendered", layout: false)
  end

  def printable_basename = "#{@printable.kind}-#{@printable.id}"

  # #532: bei Status final sind nur Status-Wechsel erlaubt (Entsperren).
  def reject_if_locked
    load_printable
    return unless @printable.locked?
    respond_to do |format|
      format.html { redirect_to printable_stack_path(@printable),
                                alert: "Dokument ist final (gesperrt).", status: :see_other }
      format.any  { head :forbidden }
    end
  end

  # #541: Dezimal-Eingabe robust parsen — Komma oder Punkt, leer = default.
  def decimal_param(raw, default: 0)
    s = raw.to_s.strip.tr(",", ".")
    return BigDecimal(default.to_s) if s.empty?
    BigDecimal(s)
  rescue ArgumentError
    BigDecimal(default.to_s)
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
end
