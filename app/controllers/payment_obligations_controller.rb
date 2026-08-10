# #1336 Stufe 2: die Zahlungspflichten eines Belegs bearbeiten — Betrag,
# Fälligkeit, Bezeichnung („Rate 2 von 4"), getilgt ja/nein.
#
# Der Betrag wird in der Oberfläche POSITIV eingegeben und geführt; das
# Vorzeichen der Geldrichtung setzt der Beleg (`obligation_sign`). So muss
# niemand im Formular über Vorzeichen nachdenken, und die Invariante
# „Vorzeichen der Pflicht = Vorzeichen des tilgenden Umsatzes" bleibt trotzdem.
class PaymentObligationsController < ApplicationController
  before_action :set_obligation
  before_action :reject_locked

  def update
    attrs = {}
    attrs[:due_on] = params[:due_on].presence                      if params.key?(:due_on)
    attrs[:label]  = params[:label].to_s.strip.presence            if params.key?(:label)
    if params.key?(:amount)
      attrs[:amount] = decimal(params[:amount]).abs * sign
      # War sie voll getilgt, bleibt sie es auch nach einer Betragskorrektur.
      attrs[:settled_amount] = attrs[:amount] if @obligation.settled? && !@obligation.amount.zero?
    end
    if params.key?(:settled)
      full = ActiveModel::Type::Boolean.new.cast(params[:settled])
      attrs[:settled_amount] = full ? (attrs[:amount] || @obligation.amount) : 0
    end
    @obligation.update!(attrs) if attrs.any?
    render_section
  end

  def destroy
    @obligation.destroy!
    render_section
  end

  private

  # Weicher Gate wie im InvoicesController — Zugriff über die Task-Capability.
  def controller_resource_type = "Task"

  def set_obligation
    @obligation = PaymentObligation.find(params[:id])
    @invoice    = @obligation.bearer.is_a?(Invoice) ? @obligation.bearer : @obligation.announced_by
  end

  def sign = @invoice&.obligation_sign || 1

  def reject_locked
    return unless @invoice&.locked?
    respond_to do |format|
      format.html { redirect_to invoices_path, alert: "Beleg ist final (gesperrt).", status: :see_other }
      format.any  { head :forbidden }
    end
  end

  def render_section
    @invoice.reload
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "invoice_payment_obligations_#{@invoice.id}",
          partial: "invoices/payment_obligations", locals: { invoice: @invoice }
        )
      end
      format.html { redirect_to invoices_path(stack: "list:invoices,invoice:#{@invoice.id}"), status: :see_other }
    end
  end

  def decimal(raw) = Dezimalbetrag.parse(raw) || BigDecimal("0")
end
