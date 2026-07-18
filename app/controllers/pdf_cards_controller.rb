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
    # #1058 (aus immoos #1042 übernommen): urlsafe_decode64 liefert BINARY —
    # ohne force_encoding knallen Nicht-ASCII-Titel (·, Umlaute) beim Rendern
    # (Encoding::CompatibilityError).
    raw = raw.to_s.dup.force_encoding(Encoding::UTF_8)
    raise ActiveRecord::RecordNotFound unless raw.valid_encoding?
    path, title = raw.split("\n", 2)
    # Nur same-origin-Pfade — keine externen URLs, kein protocol-relative "//".
    raise ActiveRecord::RecordNotFound unless path.to_s.match?(%r{\A/[^/\s]}) || path == "/"

    render partial: "pdf_cards/blade_card",
           locals: { payload: params[:payload], path: path, title: title.presence },
           layout: false
  end
end
