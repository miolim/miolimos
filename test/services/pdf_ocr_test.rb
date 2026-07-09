require "test_helper"

# #934 Stufe 2: OCR-Textlayer — defensiv: ohne ocrmypdf-Setup ist alles No-Op.
class PdfOcrTest < ActiveSupport::TestCase
  test "add_text_layer ist nil ohne ocrmypdf" do
    skip "ocrmypdf ist installiert — No-Op-Pfad nicht testbar" if PdfOcr.available?
    Dir.mktmpdir do |dir|
      path = File.join(dir, "scan.pdf")
      File.binwrite(path, "%PDF-1.4 fake")
      assert_nil PdfOcr.add_text_layer(path, dir: dir)
    end
  end

  test "text_layer? erkennt Text-PDFs (kein unnötiges OCR)" do
    pdf = DocumentPdf.render("<html><body><p>Genug Text für die Textlayer-Erkennung im Reader.</p></body></html>")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "text.pdf")
      File.binwrite(path, pdf)
      assert PdfOcr.text_layer?(path)
    end
  end
end
