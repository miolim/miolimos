# #1337 Schnitt 3 (aus immoOS #975): CAMT-Parser (ISO 20022 camt.052/053). Liest die
# Buchungen (<Ntry>) namespace-agnostisch aus und liefert normalisierte Umsatz-
# Hashes. Vorzeichen: CRDT (Gutschrift) = +Einzahlung, DBIT = −Auszahlung.
module Bank
  class CamtImport
    NO_REF = %w[NOTPROVIDED NOTAVAILABLE].freeze

    def self.parse(xml)
      require "nokogiri"
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!
      doc.xpath("//Ntry").map { |n| entry(n) }.compact
    end

    # #996 (Hans): das KONTO des Auszugs (nicht die Gegenpartei) — steht direkt
    # unter <Stmt>/<Rpt>/<Acct> (camt.053/052), NICHT in den Buchungen. Für die
    # Erkennung, zu welchem HV-Konto der Upload gehört.
    def self.account_info(xml)
      require "nokogiri"
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!
      acct = doc.at_xpath("//Stmt/Acct") || doc.at_xpath("//Rpt/Acct") || doc.at_xpath("//Acct")
      return {} unless acct
      { iban: acct.at_xpath("./Id/IBAN")&.text&.strip,
        name: acct.at_xpath("./Ownr/Nm")&.text&.strip }
    end

    def self.entry(n)
      raw = n.at_xpath("./Amt")&.text
      return nil if raw.blank?
      amt = raw.tr(",", ".").to_d
      credit = n.at_xpath("./CdtDbtInd")&.text != "DBIT"
      amt = -amt unless credit
      txd = n.at_xpath(".//TxDtls")
      party = credit ? "Dbtr" : "Cdtr"
      acct  = credit ? "DbtrAcct" : "CdtrAcct"

      {
        amount: amt,
        currency: n.at_xpath("./Amt/@Ccy")&.value.presence || "EUR",
        booked_on: date(n.at_xpath("./BookgDt")),
        value_date: date(n.at_xpath("./ValDt")),
        purpose: (txd || n).xpath(".//RmtInf/Ustrd").map { |u| u.text.strip }.join(" ").squish.presence,
        counterparty_name: find(txd, n, ".//RltdPties/#{party}/Nm", ".//#{party}/Nm"),
        counterparty_iban: find(txd, n, ".//RltdPties/#{acct}/Id/IBAN", ".//#{acct}/Id/IBAN"),
        bank_ref: bank_ref(n, txd)
      }
    end

    def self.find(txd, n, *paths)
      paths.each do |p|
        node = (txd&.at_xpath(p) || n.at_xpath(p))
        return node.text if node&.text.present?
      end
      nil
    end

    def self.bank_ref(n, txd)
      ref = n.at_xpath("./AcctSvcrRef")&.text ||
            txd&.at_xpath(".//Refs/AcctSvcrRef")&.text ||
            txd&.at_xpath(".//Refs/EndToEndId")&.text
      ref = ref.to_s.strip
      return nil if ref.blank? || NO_REF.include?(ref.upcase)
      ref
    end

    # #1337: über Bank::Datum, wie CSV und PDF auch. Ein gelesenes Datum wird
    # validiert, nicht geparst und geglaubt.
    def self.date(node)
      return nil unless node
      s = (node.at_xpath("./Dt") || node.at_xpath("./DtTm"))&.text
      Bank::Datum.parse(s.to_s[0, 10])
    end
  end
end
