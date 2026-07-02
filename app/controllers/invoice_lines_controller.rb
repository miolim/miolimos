# #541 (Hans, 2026-06-09): Rechnungsposition als eigenes Detail-Blade. Position
# und Zeiten sind getrennt — hier werden die Positionsfelder bearbeitet und
# Zeitbuchungen zugeordnet/gelöst. Sind Zeiten zugeordnet, ist die Menge die
# Summe ihrer Stunden (sonst frei wählbar).
class InvoiceLinesController < ApplicationController
  before_action :set_line

  # Detail-Blade der Position.
  def card
    render partial: "documents/invoice_line_blade_card", layout: false, locals: { line: @line }
  end

  # Felder bearbeiten (Beschreibung/Preis/USt; Menge nur ohne zugeordnete Zeiten).
  def update_line
    return reject_locked if @line.document.locked?
    attrs = {}
    attrs[:description] = params[:description]            if params.key?(:description)
    attrs[:unit_price]  = decimal(params[:unit_price])   if params.key?(:unit_price)
    attrs[:tax_rate]    = decimal(params[:tax_rate], 19) if params.key?(:tax_rate)
    if params.key?(:quantity) && !@line.time_based?
      attrs[:quantity] = decimal(params[:quantity])
      attrs[:unit]     = params[:unit].to_s.strip if params.key?(:unit)
    end
    @line.update!(attrs) if attrs.any?
    render_card
  end

  # Abrechenbare Zeitbuchung(en) dieser Position zuordnen — einzeln oder ganze
  # Item-Gruppe (time_entry_ids[]). #541 (Hans, 2026-06-09).
  def assign_time
    return reject_locked if @line.document.locked?
    ids = Array(params[:time_entry_ids]).presence || [params[:time_entry_id]].compact
    TimeEntry.where(id: ids, invoice_line_id: nil, billable: true, status: "finished")
             .update_all(invoice_line_id: @line.id)
    @line.recompute_quantity_from_times!
    render_card
  end

  # Eine zugeordnete Zeitbuchung wieder lösen (wird wieder abrechenbar).
  def unassign_time
    return reject_locked if @line.document.locked?
    te = @line.time_entries.find_by(id: params[:time_entry_id])
    if te
      te.update!(invoice_line: nil)
      @line.recompute_quantity_from_times!
    end
    render_card
  end

  private

  # #541: weicher Gate wie DocumentsController — Positionen gehören zu
  # Dokumenten; Zugriff über die (vorhandene) Task-Capability.
  def controller_resource_type = "Task"

  def set_line
    @line = InvoiceLine.find(params[:id])
  end

  # Position-Blade + (falls im DOM) die Positionsliste des Dokuments ersetzen,
  # damit die Summen sofort stimmen.
  def render_card
    @line.reload
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("stack_card_invoiceline:#{@line.id}",
            partial: "documents/invoice_line_blade_card", locals: { line: @line }),
          turbo_stream.replace("document_invoice_lines_#{@line.document_id}",
            partial: "documents/invoice_lines", locals: { document: @line.document })
        ]
      end
      format.html { redirect_to documents_path(stack: "list:documents,document:#{@line.document_id}"), status: :see_other }
    end
  end

  def reject_locked
    respond_to do |format|
      format.html { redirect_to documents_path, alert: "Dokument ist final (gesperrt).", status: :see_other }
      format.any  { head :forbidden }
    end
  end

  def decimal(raw, default = 0)
    s = raw.to_s.strip.tr(",", ".")
    s.empty? ? BigDecimal(default.to_s) : BigDecimal(s)
  rescue ArgumentError
    BigDecimal(default.to_s)
  end
end
