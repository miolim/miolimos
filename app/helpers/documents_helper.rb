module DocumentsHelper
  # #786 Inkr.2: Ausfüll-Lücke im SEPA-Mandat (leeres Feld → handschriftlich
  # ausfüllbar). Inline-Linie mit Mindestbreite.
  def ls_blank
    '<span class="ls-fill"></span>'.html_safe
  end

  # #532 Phase 2 (Hans, 2026-06-07): Briefkopf-Absenderzeilen aus einem
  # Aussteller-KI (issuer). Zieht Name, Sitz (billing- bzw. erste Adresse),
  # E-Mail und USt-IdNr aus den Stammdaten. Liefert HTML mit <br>-Trennern
  # für den .doc-sender-Block. Ohne Aussteller: leer (Partial zeigt Platzhalter).
  def document_sender_html(issuer)
    return "".html_safe unless issuer

    email = issuer.contact_points.emails.ordered.first
    phone = issuer.contact_points.phones.ordered.first

    line1 = [issuer.title, document_address_oneline(issuer)].compact_blank.join(" · ")
    # #532: E-Mail + Telefon des Absenders in den Briefkopf.
    line2 = []
    line2 << email.value if email
    line2 << "Tel. #{phone.value}" if phone
    line3 = []
    line3 << "USt-IdNr. #{document_vat_id(issuer)}" if document_vat_id(issuer).present?

    lines = [line1, line2.join(" · "), line3.join(" · ")].reject(&:blank?)
    safe_join(lines.map { |l| ERB::Util.html_escape(l) }, tag.br)
  end

  # #532: Einzeilige Absenderangabe für die DIN-5008-Rücksendeangabe im
  # Anschriftfeld (Name · Straße · PLZ Ort). Ohne Aussteller: Platzhalter.
  def document_sender_oneline(issuer)
    return "Absender — Aussteller wählen" unless issuer
    [issuer.title, document_address_oneline(issuer)].compact_blank.join(" · ")
  end

  # #532: Empfänger-Adresszeilen fürs Anschriftfeld (Name + Adresse).
  # Strukturierte Postadresse (#532), Fallback auf alten Adress-ContactPoint.
  # #694: optionale override-Postadresse (pro Dokument gewählt) durchreichen.
  def document_recipient_lines(ki, override: nil)
    return ["Empfänger — kein KI gewählt"] unless ki
    [ki.title] + document_address_lines(ki, override: override)
  end

  # Strukturierte Adresszeilen eines KI (primäre Postadresse), Fallback auf
  # den alten Adress-ContactPoint (einzeilig).
  # #694: optionale override-Postadresse (pro Dokument gewählt) hat Vorrang.
  def document_address_lines(ki, override: nil)
    return [] unless ki
    # #622: ins DIN-Fenster gehört die VERSANDanschrift (Postadresse/
    # Postfach, falls markiert) — die Rechnungs-Stammdaten (EN16931)
    # nutzen weiterhin primary_address/billing.
    if override && !override.blank?
      override.lines
    elsif (a = ki.mailing_address) && !a.blank?
      a.lines
    else
      # #762 (Hans, 2026-06-23): der einzeilige address-ContactPoint-Fallback
      # ist entfernt — Adressen kommen jetzt strukturiert aus PostalAddress.
      []
    end
  end

  def document_address_oneline(ki)
    document_address_lines(ki).join(" · ").presence
  end

  # #625 (Hans): GiroCode-SVG für eine ausgehende Rechnung (#926: Invoice-
  # Entität) — Empfänger = der Aussteller (= wir), Betrag = Bruttosumme,
  # Zweck = Rechnungsnummer. nil ohne Aussteller-IBAN oder bei Betrag 0.
  def document_giro_code_svg(invoice, module_size: 3)
    return nil unless invoice.issuer_iban.present?
    return nil unless invoice.gross_total.to_f.positive?
    ref = invoice.number.present? ? "Rechnung #{invoice.number}" : "Rechnung ##{invoice.id}"
    GiroCode.svg(
      name:       invoice.issuer&.title,
      iban:       invoice.issuer_iban,
      bic:        invoice.issuer_bic,
      amount:     invoice.gross_total,
      remittance: ref,
      module_size: module_size
    ).html_safe
  rescue GiroCode::Error => e
    Rails.logger.warn("GiroCode: #{e.message} (Invoice #{invoice.id})")
    nil
  end

  # #544/#761: USt-IdNr kommt aus dem IDs-Bereich (Identifier mit passendem
  # Label). Die alte vat_id-Spalte ist entfernt (#761).
  def document_vat_id(ki)
    return nil unless ki
    idr = ki.identifiers.detect { |i| i.label.to_s =~ /ust.?-?id|umsatzsteuer|vat/i }
    idr&.value.presence
  end

  # #532: Geld-Formatierung deutsch (1.234,56 €).
  def document_euro(amount)
    number_to_currency(amount, unit: "€", separator: ",", delimiter: ".", format: "%n %u")
  end
end
