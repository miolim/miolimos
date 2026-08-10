# #1337 Schnitt 4: Entscheidungen an einem Umsatz — einer Zahlungspflicht
# zuordnen, Zuordnung lösen, oder bewusst ohne Zuordnung lassen.
#
# „Bewusst ohne Zuordnung" ist kein Nebenschauplatz: Darlehensrate,
# Kontoführungsentgelt und Umbuchungen zwischen eigenen Konten haben keinen
# Beleg. Ohne dieses Merkmal steht ein Drittel des Kontos für immer als „nicht
# zugeordnet" da, und die Liste wird wertlos.
class BankTransactionsController < ApplicationController
  before_action :set_transaction

  def controller_resource_type = "Task"

  def assign
    obligation = PaymentObligation.find_by(id: params[:payment_obligation_id])
    if obligation && !Bank::ObligationMatch.assign(@tx, obligation, params[:amount])
      @fehler = t("bank.transactions.assign_failed")
    end
    render_card
  end

  def unassign
    settlement = @tx.obligation_settlements.find_by(id: params[:settlement_id])
    settlement ? Bank::ObligationMatch.unassign_settlement(settlement)
               : Bank::ObligationMatch.unassign(@tx)
    render_card
  end

  def no_assignment
    if @tx.no_assignment?
      @tx.clear_no_assignment!
    else
      @tx.mark_no_assignment!(params[:note])
    end
    render_card
  end

  private

  def set_transaction = @tx = BankTransaction.find(params[:id])

  def render_card
    ledger = @tx.bank_ledger.reload
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "stack_card_bankledger:#{ledger.id}",
          partial: "bank_ledgers/blade_card", locals: { ledger: ledger, fehler: @fehler }
        )
      end
      format.html do
        redirect_to bank_ledgers_path(stack: "list:bank_ledgers,bankledger:#{ledger.id}"),
                    status: :see_other
      end
    end
  end
end
