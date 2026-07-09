# #934 (Hans, 2026-07-09): ZUGFeRD/Factur-X-Extraktion für EINGEHENDE
# Rechnungen — das deterministische Gegenstück zum ZugferdGenerator.
# Liest die in einer Hybrid-PDF eingebettete EN16931-CII-XML über dasselbe
# Python-venv (factur-x) und liefert die Kernfelder als Hash; nil, wenn
# die PDF keine E-Rechnung ist (dann übernimmt die LLM-Extraktion).
require "open3"

class ZugferdReader
  PYTHON = ZugferdGenerator::PYTHON
  SCRIPT = ZugferdGenerator::SCRIPT

  class Error < StandardError; end

  def self.available? = ZugferdGenerator.available?

  # → Hash (Symbol-Keys wie im Skript-JSON: number, issue_date, seller,
  #   buyer, lines, due_date, totals, iban, …) oder nil (keine XML).
  def self.extract(pdf_path)
    out, err, status = Open3.capture3("timeout", "60", PYTHON, SCRIPT.to_s,
                                      "--mode", "extract", "--pdf", pdf_path.to_s)
    return nil if status.exitstatus == 3   # keine eingebettete EN16931-XML
    unless status.success?
      raise Error, status.exitstatus == 124 ? "ZUGFeRD-Extraktion Timeout (60s)" : (err.presence || "unbekannter Fehler")
    end
    JSON.parse(out)
  rescue JSON::ParserError => e
    raise Error, "ZUGFeRD-Extraktion lieferte kein JSON: #{e.message}"
  end
end
