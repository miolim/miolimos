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

  # #1675: Der geprüfte, noch nicht bestätigte Auszug liegt als DATEI auf dem
  # Server; die Session trägt nur den Schlüssel dazu. Vorher lag der ganze
  # Inhalt in der Session — die ist ein Cookie mit 4 KB, und jeder echte Auszug
  # ist größer (CookieOverflow beim Hochladen).
  ABLAGE      = Rails.root.join("tmp", "bank_uploads")
  ABLAGE_ALTER = 1.day

  # Stufe 1: prüfen, nichts schreiben. Der Auszug wartet in der Ablage, bis
  # bestätigt wird.
  def upload
    datei = params[:file]
    return render_card if datei.blank?

    inhalt = datei.read
    inhalt = Bank::PdfImport.extract(inhalt) if Bank::PdfImport.pdf?(inhalt)
    @vorschau = Bank::Import.detect(inhalt)
    @rohtext  = inhalt
    session[:bank_upload] = { "ledger_id" => @ledger.id, "filename" => datei.original_filename,
                              "schluessel" => ablegen(inhalt) }
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

    inhalt = abholen(upload["schluessel"])
    if inhalt.nil?
      session.delete(:bank_upload)
      @fehler = t("bank.import.upload_expired")
      return render_card
    end

    @ergebnis = Bank::Import.call(@ledger, inhalt, filename: upload["filename"],
                                  trotz_abweichung: params[:trotz_abweichung].present?)
    # Nach dem Import zuordnen — nur eindeutige, betragsexakte Treffer.
    @zugeordnet = Bank::ObligationMatch.auto(@ledger) if @ergebnis.imported.positive?
    wegraeumen(upload["schluessel"])
    session.delete(:bank_upload)
    render_card
  end

  def auto_match
    @zugeordnet = Bank::ObligationMatch.auto(@ledger)
    render_card
  end

  private

  def set_ledger = @ledger = BankLedger.find(params[:id])

  # Der Schlüssel ist zufällig und wird nie aus Nutzereingaben gebildet; beim
  # Abholen zählt trotzdem nur die Hex-Form (kein Pfad aus der Session heraus).
  def ablegen(inhalt)
    FileUtils.mkdir_p(ABLAGE, mode: 0o700)
    alte_wegraeumen
    wegraeumen(session.dig(:bank_upload, "schluessel"))   # ein früherer, nie bestätigter Upload
    schluessel = SecureRandom.hex(16)
    File.binwrite(ABLAGE.join(schluessel), inhalt, perm: 0o600)
    schluessel
  end

  def abholen(schluessel)
    return nil unless schluessel.to_s.match?(/\A\h{32}\z/)
    pfad = ABLAGE.join(schluessel)
    File.exist?(pfad) ? File.binread(pfad).force_encoding("UTF-8") : nil
  end

  def wegraeumen(schluessel)
    return unless schluessel.to_s.match?(/\A\h{32}\z/)
    FileUtils.rm_f(ABLAGE.join(schluessel))
  end

  # Nie bestätigte Uploads bleiben nicht ewig liegen (es sind Kontodaten).
  def alte_wegraeumen
    Dir.glob(ABLAGE.join("*")).each do |pfad|
      FileUtils.rm_f(pfad) if File.mtime(pfad) < ABLAGE_ALTER.ago
    end
  end

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
