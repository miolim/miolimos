# #926 Stufe 1 (Hans, 2026-07-09): das Erstellungs-Verfahren, entitäts-
# agnostisch — vorher lag es verstreut in DocumentsController. Nimmt eine
# druckbare Entität (Printable-Concern) + ihr gerendertes HTML und macht
# daraus PDF / signiertes PDF / festgeschriebenes Artefakt. Die einzigen
# entitäts-spezifischen Teile kommen als Hooks aus dem Modell:
# print_paged? (mehrseitig mit Fußzeile, z.B. NDA) und print_doc_id.
class DocumentRenderer
  # HTML → PDF-Bytes. Wirft DocumentPdf::Error.
  def self.pdf(printable, html)
    if printable.print_paged?
      # #562 (Hans): mehrseitiges Dokument mit Rändern + Fußzeile (Seitenzahl
      # + Dokument-ID) auf jeder Seite (Ferrum/CDP).
      DocumentPdf.render_paged(html, footer_html: footer_html(printable))
    else
      # DIN-Geometrie via @page/CSS, einfacher CLI-Render.
      DocumentPdf.render(html)
    end
  end

  # #547: PDF mit kryptografischer PAdES-Signatur (pyHanko) darüber.
  # Wirft DocumentPdf::Error / DocumentSigner::Error.
  def self.signed_pdf(printable, html, reason:)
    DocumentSigner.sign(pdf(printable, html), reason: reason)
  end

  # #532: den aktuellen Stand dauerhaft festschreiben — PDF rendern,
  # signieren (wenn das Setup da ist) und als Artefakt persistieren.
  def self.archive!(printable, html, creator:)
    bytes  = pdf(printable, html)
    signed = DocumentSigner.available?
    bytes  = DocumentSigner.sign(bytes, reason: "Finaler Stand: #{printable.issuer&.title}") if signed
    printable.document_artifacts.create!(pdf: bytes, signed: signed, creator: creator)
  end

  # Chrome-Footer-Template: links die Dokument-ID, rechts „Seite X von Y".
  # font-size MUSS inline stehen (Chrome resettet sonst auf 0); die Klassen
  # pageNumber/totalPages füllt Chrome beim Druck.
  def self.footer_html(printable)
    id = ERB::Util.html_escape(printable.print_doc_id)
    %(<div style="font-size:7pt; width:100%; padding:0 20mm 0 25mm; color:#555; ) +
      %(font-family:Helvetica,Arial,sans-serif; display:flex; justify-content:space-between;">) +
      %(<span>#{id}</span>) +
      %(<span>Seite <span class="pageNumber"></span> von <span class="totalPages"></span></span></div>)
  end
end
