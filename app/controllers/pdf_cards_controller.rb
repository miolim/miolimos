# #1025 (aus immoos übernommen, #1057): PDFs (PDF-Stände, Belege) in einer
# Stack-Card statt im Browser-Tab öffnen. Die Card bettet den (same-origin)
# PDF-Endpunkt per <embed> ein — Berechtigungen erzwingt weiterhin der
# jeweilige Endpunkt.
# payload = base64url("<pfad>\n<titel>"), damit die Stack-Id (pdfcard:<payload>)
# über Reloads/Stack-Restore stabil serialisierbar bleibt.
class PdfCardsController < ApplicationController
  def controller_resource_type = "Task"  # weicher Gate wie die Rechnungsliste (V1)

  def card
    raw = begin
      Base64.urlsafe_decode64(params[:payload].to_s)
    rescue ArgumentError
      nil
    end
    path, title = raw.to_s.split("\n", 2)
    # Nur same-origin-Pfade — keine externen URLs, kein protocol-relative "//".
    raise ActiveRecord::RecordNotFound unless path.to_s.match?(%r{\A/[^/\s]}) || path == "/"

    render partial: "pdf_cards/blade_card",
           locals: { payload: params[:payload], path: path, title: title.presence },
           layout: false
  end
end
