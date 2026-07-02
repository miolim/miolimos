require "test_helper"

# #564: PDF-Render-Strecke einfrieren. Beide Pfade (CLI für DIN-Dokumente,
# Ferrum/CDP für die NDA mit Fußzeile) müssen valide PDF-Bytes liefern.
# Chrome ist auf der Box vorhanden; anderswo skip statt rot.
class DocumentPdfTest < ActiveSupport::TestCase
  HTML = <<~HTML
    <!doctype html><html><head><meta charset="utf-8"></head>
    <body><h1>Render-Test</h1><p>Hallo PDF.</p></body></html>
  HTML

  def chrome?
    # CHROME ist ein Binary-Name (kein Pfad) — via `which` im PATH auflösen.
    @chrome ||= system("which", DocumentPdf::CHROME, out: File::NULL, err: File::NULL)
  end

  test "render (CLI): liefert valide PDF-Bytes" do
    skip "Chrome nicht vorhanden" unless chrome?
    pdf = DocumentPdf.render(HTML)
    assert pdf.bytesize > 1_000, "PDF verdächtig klein (#{pdf.bytesize} B)"
    assert pdf.start_with?("%PDF-"), "kein PDF-Magic"
  end

  test "render_paged (Ferrum): liefert valide PDF-Bytes mit Footer-Option" do
    skip "Chrome nicht vorhanden" unless chrome?
    footer = %(<div style="font-size:7pt; width:100%; text-align:center;">) +
             %(ID-TEST <span class="pageNumber"></span>/<span class="totalPages"></span></div>)
    pdf = DocumentPdf.render_paged(HTML, footer_html: footer)
    assert pdf.bytesize > 1_000, "PDF verdächtig klein (#{pdf.bytesize} B)"
    assert pdf.start_with?("%PDF-"), "kein PDF-Magic"
  end

  test "render: Timeout/Fehler wird als DocumentPdf::Error gemeldet" do
    # Nicht existierendes Chrome-Binary → system() schlägt fehl → Error,
    # keine Exception anderer Klasse, kein Hängen.
    original = DocumentPdf::CHROME
    DocumentPdf.send(:remove_const, :CHROME)
    DocumentPdf.const_set(:CHROME, "/nonexistent/chrome-bin")
    assert_raises(DocumentPdf::Error) { DocumentPdf.render(HTML) }
  ensure
    DocumentPdf.send(:remove_const, :CHROME)
    DocumentPdf.const_set(:CHROME, original)
  end
end
