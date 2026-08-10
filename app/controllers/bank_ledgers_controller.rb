# #1337 Schnitt 4: die Konto-Card — Bankkonto mit Umsatzliste, Auszugs-Import
# und Zuordnung.
#
# Der Import läuft ZWEISTUFIG: Erst wird die Datei geprüft (welches Konto,
# welches Format, wie viele Buchungen, geht bei einem PDF der Saldo auf?) und
# das Ergebnis angezeigt — geschrieben wird erst auf Bestätigung. Bei Geld
# gehört ein Mensch vor die Persistenz.
class BankLedgersController < ApplicationController
  before_action :set_ledger, only: [:card, :update, :destroy, :upload, :import, :auto_match]

  # Zugriff über die vorhandene Task-Capability, wie bei den Belegen.
  def controller_resource_type = "Task"

  def index; end

  def list_card
    render partial: "bank_ledgers/list_blade_card", layout: false
  end

  def card
    render partial: "bank_ledgers/blade_card", layout: false, locals: { ledger: @ledger }
  end

  def create
    ledger = BankLedger.create!(label: params[:label].presence || t("bank.ledgers.new_label"),
                                iban: params[:iban].presence)
    redirect_to bank_ledgers_path(stack: "list:bank_ledgers,bankledger:#{ledger.id}"),
                status: :see_other
  end

  def update
    attrs = params.permit(:label, :iban, :bic, :bank_name, :holder, :opening_on).to_h.compact
    attrs[:opening_balance] = Dezimalbetrag.parse(params[:opening_balance]) if params.key?(:opening_balance)
    @ledger.update!(attrs) if attrs.any?
    render_card
  end

  def destroy
    @ledger.destroy!
    redirect_to bank_ledgers_path(stack: "list:bank_ledgers"), status: :see_other
  end

  # Stufe 1: prüfen, nichts schreiben. Das Ergebnis liegt als
  # BankStatementUpload in der Session-Ablage, bis bestätigt wird.
  def upload
    datei = params[:file]
    return render_card if datei.blank?

    inhalt = datei.read
    inhalt = Bank::PdfImport.extract(inhalt) if Bank::PdfImport.pdf?(inhalt)
    @vorschau = Bank::Import.detect(inhalt)
    @rohtext  = inhalt
    session[:bank_upload] = { "ledger_id" => @ledger.id, "filename" => datei.original_filename,
                              "content" => inhalt }
    render_card
  rescue Bank::PdfImport::Error => e
    @fehler = e.message
    render_card
  end

  # Stufe 2: schreiben. `trotz_abweichung` nur, wenn ausdrücklich gewollt —
  # der Auszug trägt danach den Vermerk.
  def import
    upload = session[:bank_upload]
    return render_card if upload.blank? || upload["ledger_id"] != @ledger.id

    @ergebnis = Bank::Import.call(@ledger, upload["content"], filename: upload["filename"],
                                  trotz_abweichung: params[:trotz_abweichung].present?)
    # Nach dem Import zuordnen — nur eindeutige, betragsexakte Treffer.
    @zugeordnet = Bank::ObligationMatch.auto(@ledger) if @ergebnis.imported.positive?
    session.delete(:bank_upload)
    render_card
  end

  def auto_match
    @zugeordnet = Bank::ObligationMatch.auto(@ledger)
    render_card
  end

  private

  def set_ledger = @ledger = BankLedger.find(params[:id])

  def render_card
    @ledger.reload
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "stack_card_bankledger:#{@ledger.id}",
          partial: "bank_ledgers/blade_card",
          locals: { ledger: @ledger, vorschau: @vorschau, ergebnis: @ergebnis,
                    zugeordnet: @zugeordnet, fehler: @fehler }
        )
      end
      format.html do
        redirect_to bank_ledgers_path(stack: "list:bank_ledgers,bankledger:#{@ledger.id}"),
                    status: :see_other
      end
    end
  end
end
