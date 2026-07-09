# #934 Stufe 2 (Hans, 2026-07-09): durchsuchbarer Textlayer für gescannte
# PDFs — OCRmyPDF (wrappt Tesseract) legt einen unsichtbaren Textlayer über
# die Seiten; die Optik bleibt identisch, Strg+F im Viewer funktioniert.
# Nur für die ABLAGE-Kopie (Beleg-KI) — die Datenextraktion braucht kein
# OCR (Claude liest Scans direkt), das Original-Artefakt bleibt unberührt.
#
# Setup auf der Box: `sudo apt install ocrmypdf tesseract-ocr-deu` —
# fehlt es, wird der Schritt still übersprungen (available? = false).
require "open3"

class PdfOcr
  OCRMYPDF = ENV.fetch("OCRMYPDF_BIN", "ocrmypdf")

  class Error < StandardError; end

  def self.available?
    @available = system("which", OCRMYPDF, out: File::NULL, err: File::NULL) if @available.nil?
    @available
  end

  # Hat die PDF schon einen Textlayer? (Dann ist OCR unnötig.)
  def self.text_layer?(path)
    out, _err, status = Open3.capture3("pdftotext", "-l", "3", path.to_s, "-")
    status.success? && out.to_s.strip.length > 20
  rescue
    true   # im Zweifel kein OCR erzwingen
  end

  # Erzeugt eine Kopie mit Textlayer und liefert deren Pfad (im übergebenen
  # Zielverzeichnis); nil, wenn OCR nicht verfügbar/nicht nötig/fehlschlägt.
  # --skip-text lässt Seiten mit vorhandenem Text unangetastet.
  def self.add_text_layer(path, dir:)
    return nil unless available?
    return nil if text_layer?(path)
    out_path = File.join(dir, "ocr-#{File.basename(path)}")
    _out, err, status = Open3.capture3("timeout", "300", OCRMYPDF,
                                       "--skip-text", "-l", "deu+eng",
                                       "--output-type", "pdf",
                                       path.to_s, out_path)
    unless status.success? && File.exist?(out_path)
      Rails.logger.warn("PdfOcr: ocrmypdf fehlgeschlagen (exit #{status.exitstatus}): #{err.to_s.truncate(300)}")
      return nil
    end
    out_path
  end
end
