# #541 (Hans, 2026-06-09): ZUGFeRD/XRechnung-Erzeugung. Sammelt die EN16931-
# Daten aus einer Invoice (#926; vorher Document) und ruft das Python-Skript
# (drafthorse + factur-x im isolierten venv) auf — analog zum Signier-Setup (#547).
#   - xml(doc)         -> EN16931-CII-XML (XRechnung)
#   - zugferd_pdf(doc) -> ZUGFeRD-PDF/A-3 (sichtbare PDF + eingebettete XML)
require "open3"
require "tmpdir"

class ZugferdGenerator
  PYTHON = ENV.fetch("ZUGFERD_PYTHON", File.expand_path("~/.venvs/miolimos-zugferd/bin/python"))
  SCRIPT = Rails.root.join("lib/python/make_zugferd.py")

  class Error < StandardError; end

  def self.available? = File.executable?(PYTHON) && File.exist?(SCRIPT)

  def self.xml(document)
    run(["--mode", "xml"], payload(document))
  end

  # visible_pdf_bytes = die gerenderte sichtbare Rechnungs-PDF.
  def self.zugferd_pdf(document, visible_pdf_bytes)
    Dir.mktmpdir("zugferd") do |dir|
      vis = File.join(dir, "visible.pdf")
      out = File.join(dir, "zugferd.pdf")
      File.binwrite(vis, visible_pdf_bytes)
      run(["--mode", "pdf", "--pdf", vis, "--out", out], payload(document))
      File.binread(out)
    end
  end

  def self.payload(doc)
    vat = tax_no = nil
    doc.issuer_tax_ids.each do |label, value|
      if label.to_s =~ /ust.?-?id|umsatzsteuer|vat/i then vat ||= value else tax_no ||= value end
    end
    {
      number:        doc.number.presence || "ENTWURF",
      issue_date:    (doc.document_date || Date.current).strftime("%Y-%m-%d"),
      currency:      "EUR",
      seller:        party(doc.issuer).merge(vat_id: vat, tax_number: tax_no),
      buyer:         party(doc.recipient),
      service_start: doc.service_start&.strftime("%Y-%m-%d"),
      service_end:   doc.service_end&.strftime("%Y-%m-%d"),
      vat_exempt:    doc.vat_exempt?,
      lines:         doc.invoice_lines.ordered.map { |l|
        { name: l.description.presence || "Leistung",
          qty: dec(l.quantity), unit: (l.unit.to_s =~ /std|stunde|hour/i ? "HUR" : "C62"),
          unit_price: dec(l.unit_price), net: dec(l.net), tax_rate: dec(l.tax_rate) }
      },
      tax_breakdown: doc.tax_breakdown.map { |g| { rate: dec(g[:rate]), net: dec(g[:net]), tax: dec(g[:tax]) } },
      net_total:     dec(doc.net_total),
      tax_total:     dec(doc.tax_total),
      gross_total:   dec(doc.gross_total),
      iban:          doc.issuer_iban,
      bic:           doc.issuer_bic
    }
  end

  def self.party(ki)
    return { name: "—", country: "DE" } unless ki
    a = ki.primary_address
    { name: ki.title, line1: a&.line1, postcode: a&.postal_code, city: a&.city,
      country: country_code(a&.country) }
  end

  # EN16931 will den ISO-Code; deutsche Klartextnamen auf DE mappen, sonst Default.
  def self.country_code(c)
    return "DE" if c.blank? || c.to_s =~ /deutsch|german/i
    c.to_s.length == 2 ? c.to_s.upcase : "DE"
  end

  def self.dec(v) = format("%.2f", v.to_f)

  def self.run(args, payload)
    # #541: BR-CO-26 — ohne USt-IdNr ODER Steuernummer kann der Käufer den
    # Verkäufer nicht identifizieren; klare Meldung statt rohem Schematron-Fehler.
    s = payload[:seller] || {}
    if s[:vat_id].blank? && s[:tax_number].blank?
      raise Error, "Der Aussteller braucht eine USt-IdNr oder Steuernummer (in den IDs des Aussteller-Kontakts hinterlegen) — sonst lässt sich keine gültige e-Rechnung (ZUGFeRD/XRechnung) erzeugen."
    end
    # #564: coreutils-timeout als harte Obergrenze — ein hängender Python-
    # Prozess darf keinen Puma-Worker blockieren (Exit 124 = Timeout).
    out, err, status = Open3.capture3("timeout", "60", PYTHON, SCRIPT.to_s, *args,
                                      stdin_data: payload.to_json, binmode: true)
    unless status.success?
      raise Error, status.exitstatus == 124 ? "ZUGFeRD-Erzeugung Timeout (60s)" : (err.presence || "unbekannter Fehler")
    end
    out
  end
end
