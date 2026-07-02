require "rqrcode"

# #625 (Hans, 2026-06-14): EPC-QR / „GiroCode" — der offene Banken-Standard
# (EPC069-12), den deutsche Banking-Apps nativ scannen. Reiner Text-Payload,
# kein Dienst dazwischen, keine Krypto. Auf ausgehende Rechnungen drucken
# (Kunde scannt → zahlt uns) und für das Überweisungs-Formular.
class GiroCode
  class Error < StandardError; end

  # EPC069-12-Text-Payload. amount in EUR (Float/BigDecimal), optional —
  # ohne Betrag fragt die App den Betrag beim Scannen ab.
  def self.payload(name:, iban:, amount: nil, remittance: nil, bic: nil, reference: nil)
    iban = iban.to_s.gsub(/\s+/, "").upcase
    raise Error, "IBAN fehlt" if iban.blank?
    name = name.to_s.strip
    raise Error, "Empfängername fehlt" if name.blank?

    amount_str =
      if amount.present? && amount.to_f.positive?
        a = amount.to_f.round(2)
        raise Error, "Betrag außerhalb 0,01–999999999,99 €" unless a.between?(0.01, 999_999_999.99)
        format("EUR%.2f", a)
      else
        ""
      end

    [
      "BCD",                                # Service-Tag
      "002",                                # Version (002 erlaubt BIC leer)
      "1",                                  # Zeichensatz 1 = UTF-8
      "SCT",                                # SEPA Credit Transfer
      bic.to_s.gsub(/\s+/, "").upcase,      # BIC (bei SEPA optional)
      name[0, 70],                          # Empfängername
      iban,                                 # Empfänger-IBAN
      amount_str,                           # Betrag (EUR12.50) oder leer
      "",                                   # Purpose-Code (4 Zeichen, optional)
      reference.to_s.strip[0, 35],          # strukturierte Referenz (optional)
      remittance.to_s.strip[0, 140]         # unstrukturierter Verwendungszweck
    ].join("\n")
  end

  # Inline-SVG des QR-Codes — rendert im Browser-Blade UND im Chrome-PDF.
  def self.svg(module_size: 3, **kwargs)
    qr = RQRCode::QRCode.new(payload(**kwargs), level: :m)
    qr.as_svg(module_size: module_size, standalone: true, use_path: true,
              color: "000", shape_rendering: "crispEdges")
  end
end
