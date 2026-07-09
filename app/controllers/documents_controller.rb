# #532 (Hans, 2026-06-07) / #926 (2026-07-09): das ANSCHREIBEN (Brief/NDA/
# SEPA-Mandat). Rechnung/Angebot leben seit #926 im InvoicesController;
# das gemeinsame Erstellungs-Verfahren (Blade, Auto-Save, Picker, Felder,
# PDF/Signatur/Festschreiben, Papierkorb) kommt aus PrintableResource.
# Hier bleibt nur, was das Anschreiben ausmacht: der Freitext-Body (KI),
# die Typ-Spielarten (NDA-Parteien, Lastschrift-Konto) und die
# Theme-Werkbank (preview/pdf mit Beispieldaten).
class DocumentsController < ApplicationController
  include KnowledgeStackHelpers
  include PrintableResource

  # #532: bei Status final sind Feld-Mutationen gesperrt (nur Status-Wechsel
  # zurück auf Entwurf entsperrt wieder).
  before_action :reject_if_locked, only: [:link, :create_body_ki, :document_fields, :select_identifiers]

  SAMPLES = { "invoice" => "Rechnung", "nda" => "NDA", "letter" => "Brief" }.freeze

  # #532 (Hans, 2026-06-08): Anzeige-Labels der Anschreiben-Arten.
  KIND_LABELS     = { "brief" => "Brief", "nda" => "NDA",
                      "lastschrift" => "SEPA-Lastschriftmandat" }.freeze   # #786
  CREATABLE_KINDS = %w[brief nda lastschrift].freeze

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

  # Neues Dokument anlegen — Vordialog wählt den Typ.
  def create
    kind = params[:kind].to_s
    unless CREATABLE_KINDS.include?(kind)
      redirect_to documents_path, alert: "Dieser Dokumenttyp kann noch nicht angelegt werden."
      return
    end
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

  # #532 (Hans, 2026-06-08): ein neues Text-KI anlegen und gleich als Body
  # verknüpfen. Titel-Schema: "Brief - YYYY-MM-DD [Empfänger] [Betreff]".
  def create_body_ki
    load_printable
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

  private

  def printable_model = Document

  def printable_stack_path(doc)
    documents_path(stack: "list:documents,document:#{doc.id}")
  end

  # Wendet die skalaren Meta-Felder an (Auto-Save). Verknüpfungen laufen
  # über #link (entity-picker).
  def apply_printable_params!(doc)
    attrs = {}
    attrs[:subject]       = params[:subject]                if params.key?(:subject)
    attrs[:salutation]    = params[:salutation]             if params.key?(:salutation)
    attrs[:document_date] = params[:document_date].presence if params.key?(:document_date)
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
    doc.update!(attrs) if attrs.any?
  end

  # #532: Picker-Scopes des Anschreibens (zusätzlich zum Concern: body).
  def suggest_scope(kind)
    case kind
    when "issuer"    then KnowledgeItem.issuers
    when "recipient" then KnowledgeItem.persons_and_orgs
    when "body"      then KnowledgeItem.where(item_type: %i[note abstract doc synthesis])
    end
  end

  # Anschreiben-eigenes link-Feld: der Freitext-Body (KI).
  def link_extra_field!(field, value)
    return false unless field == "body"
    @document.update!(body_ki_uuid: resolve_ki(value, KnowledgeItem.all))
    true
  end

  # #766 (Hans): Vorlagentext eines Dokumenttyps aus den DATEN holen — eine
  # Notiz-KI mit Tag "vorlage:<kind>" (z.B. "vorlage:nda"). Existiert keine,
  # bleibt der Body leer. Bewusst NICHT im Code, da dieser veröffentlicht wird.
  def document_template_body(kind)
    KnowledgeItem.where(item_type: "note")
                 .where("? = ANY(tags)", "vorlage:#{kind}")
                 .order(:created_at).first&.body.to_s
  end

  # #532: Aussteller-KIs für den Briefkopf. @issuer = gewählter (Param) oder
  # erster markierter Aussteller; @issuers für die Werkbank-Auswahl.
  def load_issuers
    @issuers = KnowledgeItem.issuers.order(Arel.sql("LOWER(title) ASC"))
    @issuer  = (@issuers.find_by(uuid: params[:issuer]) if params[:issuer].present?) ||
               @issuers.first
  end

  def controller_resource_type = "Task"  # weicher Gate (V1)
end
