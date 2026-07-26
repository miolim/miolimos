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

  # #1168: Logo des Ausstellers als Data-URI einbetten — die Dokument-HTMLs
  # müssen selbst-enthalten sein (Headless-Chrome-PDF ohne Asset-Server,
  # siehe DocumentPdf). Liefert nil, wenn kein Logo hinterlegt ist oder die
  # Datei fehlt; der Briefkopf fällt dann auf den Ausstellernamen zurück.
  def document_logo_tag(issuer)
    logo = issuer&.logo
    return nil if logo&.file_path.blank?
    full = FileProxy::BASE_PATH.join(logo.file_path)
    return nil unless File.exist?(full)
    mime = Mime::Type.lookup_by_extension(File.extname(full).delete(".").downcase).to_s
    return nil unless mime.start_with?("image/")
    data = Base64.strict_encode64(File.binread(full))
    image_tag("data:#{mime};base64,#{data}", alt: issuer.title, class: "doc-logo-img")
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
  # #1090 Nachtrag: akademischer Titel vor dem Namen („Prof. Dr. Erika
  # Meier") — DIN 5008 führt den Titel in der Namenszeile.
  def document_recipient_lines(ki, override: nil)
    return ["Empfänger — kein KI gewählt"] unless ki
    name = [ki.academic_title.presence, ki.title].compact.join(" ")
    [name] + document_address_lines(ki, override: override)
  end

  # #1171 (aus immoOS #1069): Anschriftfeld eines Belegs — kann MEHRERE
  # Namenszeilen haben; eine hinterlegte Kurzform („Eheleute Mustermann")
  # ersetzt die Namenszeilen. Die Adresse kommt weiterhin vom `recipient` —
  # die gemeinsame Wohnung ist dieselbe, ein zweiter Adressblock wäre falsch.
  def printable_recipient_lines(printable)
    ki = printable.recipient
    return ["Empfänger — kein KI gewählt"] unless ki
    names = printable.recipient_name_lines.presence || [ki.title]
    names + document_address_lines(ki, override: printable.chosen_recipient_address)
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

  # #1171 (aus immoOS #1157 E4): GiroCode auf dem ANSCHREIBEN — daten-
  # getrieben über die Infoblock-Felder „Zahlbetrag" (+ optional
  # „Verwendungszweck"). IBAN/BIC: Identifier des Ausstellers (wie
  # Rechnung), sonst dessen erste Bankverbindung. Betrag komma-bewusst
  # via Dezimalbetrag (immoOS #1170).
  def document_giro_code_brief(document, module_size: 3)
    return nil unless document.brief?
    fields = document.document_fields.index_by { |f| TemplateMerge.normalize_key(f.label) }
    amount = Dezimalbetrag.parse(fields["zahlbetrag"]&.value)
    return nil unless amount&.positive?
    account = document.issuer&.bank_accounts&.ordered&.first
    iban = document.issuer_iban.presence || account&.iban
    return nil if iban.blank?
    GiroCode.svg(
      name:       document.issuer&.title,
      iban:       iban,
      bic:        document.issuer_bic.presence || account&.bic,
      amount:     amount,
      remittance: fields["verwendungszweck"]&.value,
      module_size: module_size
    ).html_safe
  rescue GiroCode::Error => e
    Rails.logger.warn("GiroCode: #{e.message} (Document #{document.id})")
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
