#!/usr/bin/env python3
"""#541 (Hans, 2026-06-09): ZUGFeRD/XRechnung-Erzeugung (+ #934: -Extraktion).

Liest ein JSON-Payload (Rechnungsdaten, EN16931) von stdin und erzeugt
- mode=xml: die EN16931-CII-XML (für XRechnung) -> stdout (bytes)
- mode=pdf: bettet die XML in die sichtbare PDF ein und liefert eine
            ZUGFeRD-PDF/A-3 -> Datei (--out), Quell-PDF via --pdf
- mode=extract (#934): liest die in einer eingehenden ZUGFeRD/Factur-X-PDF
            eingebettete EN16931-CII-XML und liefert die Kernfelder als
            JSON -> stdout. Exit 3, wenn die PDF keine XML enthält.

Aufruf:  python make_zugferd.py --mode xml < payload.json
         python make_zugferd.py --mode pdf --pdf visible.pdf --out out.pdf < payload.json
         python make_zugferd.py --mode extract --pdf eingang.pdf
"""
import sys, json, argparse, io
from datetime import datetime, timedelta
from decimal import Decimal

from drafthorse.models.document import Document
from drafthorse.models.tradelines import LineItem
from drafthorse.models.party import TaxRegistration
from drafthorse.models.accounting import ApplicableTradeTax
from drafthorse.models.payment import PaymentMeans, PaymentTerms
import xml.etree.ElementTree as ET


def D(x):
    return Decimal(str(x if x not in (None, "") else "0"))


def build_xml(p):
    doc = Document()
    doc.context.guideline_parameter.id = "urn:cen.eu:en16931:2017"
    doc.header.id = p["number"]
    doc.header.type_code = "380"  # Handelsrechnung
    doc.header.issue_date_time = datetime.strptime(p["issue_date"], "%Y-%m-%d").date()

    # ── Verkäufer ──
    s = p["seller"]
    seller = doc.trade.agreement.seller
    seller.name = s["name"]
    seller.address.line_one = s.get("line1", "")
    seller.address.postcode = s.get("postcode", "")
    seller.address.city_name = s.get("city", "")
    seller.address.country_id = s.get("country", "DE")
    if s.get("vat_id"):
        tr = TaxRegistration(); tr.id = ("VA", s["vat_id"]); seller.tax_registrations.add(tr)
    if s.get("tax_number"):
        tr = TaxRegistration(); tr.id = ("FC", s["tax_number"]); seller.tax_registrations.add(tr)
    # BR-CO-26: Verkäufer muss BT-29/30/31 haben. Ohne USt-IdNr (BT-31) die
    # Steuernummer zusätzlich als Verkäufer-Kennung (BT-29) setzen, sonst
    # scheitert die Schematron-Validierung (Kleinunternehmer ohne USt-IdNr).
    if not s.get("vat_id") and s.get("tax_number"):
        seller.id = s["tax_number"]

    # ── Käufer ──
    b = p["buyer"]
    buyer = doc.trade.agreement.buyer
    buyer.name = b["name"]
    buyer.address.line_one = b.get("line1", "")
    buyer.address.postcode = b.get("postcode", "")
    buyer.address.city_name = b.get("city", "")
    buyer.address.country_id = b.get("country", "DE")

    exempt = bool(p.get("vat_exempt"))
    cat = "E" if exempt else "S"  # E = befreit, S = Standardsatz

    # ── Positionen ──
    for i, ln in enumerate(p["lines"], start=1):
        li = LineItem()
        li.document.line_id = str(i)
        li.product.name = ln.get("name") or "Leistung"
        li.agreement.net.amount = D(ln["unit_price"])
        li.delivery.billed_quantity = (D(ln["qty"]), ln.get("unit") or "C62")
        li.settlement.trade_tax.type_code = "VAT"
        li.settlement.trade_tax.category_code = cat
        li.settlement.trade_tax.rate_applicable_percent = D(0 if exempt else ln["tax_rate"])
        li.settlement.monetary_summation.total_amount = D(ln["net"])
        doc.trade.items.add(li)

    # ── Steueraufschlüsselung ──
    if exempt:
        tax = ApplicableTradeTax()
        tax.calculated_amount = D(0)
        tax.basis_amount = D(p["net_total"])
        tax.type_code = "VAT"
        tax.category_code = "E"
        tax.rate_applicable_percent = D(0)
        tax.exemption_reason = "Steuerbefreit gemäß § 19 UStG (Kleinunternehmer)"
        doc.trade.settlement.trade_tax.add(tax)
    else:
        for g in p["tax_breakdown"]:
            tax = ApplicableTradeTax()
            tax.calculated_amount = D(g["tax"])
            tax.basis_amount = D(g["net"])
            tax.type_code = "VAT"
            tax.category_code = "S"
            tax.rate_applicable_percent = D(g["rate"])
            doc.trade.settlement.trade_tax.add(tax)

    issue = datetime.strptime(p["issue_date"], "%Y-%m-%d").date()

    # ── Leistungsdatum (BT-72, Pflicht) + Leistungszeitraum (BG-14) ──
    deliv = datetime.strptime(p.get("service_end") or p.get("service_start") or p["issue_date"], "%Y-%m-%d").date()
    doc.trade.delivery.event.occurrence = deliv
    if p.get("service_start"):
        doc.trade.settlement.period.start = datetime.strptime(p["service_start"], "%Y-%m-%d").date()
        doc.trade.settlement.period.end = datetime.strptime(p.get("service_end") or p["service_start"], "%Y-%m-%d").date()

    # ── Zahlungsbedingungen (BT-20/BT-9) — sonst BR-CO-25 ──
    pt = PaymentTerms()
    pt.description = "Zahlbar innerhalb von 14 Tagen ohne Abzug."
    pt.due = issue + timedelta(days=14)
    doc.trade.settlement.terms.add(pt)

    # ── Zahlung ──
    if p.get("iban"):
        pm = PaymentMeans()
        pm.type_code = "58"  # SEPA-Überweisung
        pm.payee_account.iban = p["iban"]
        if p.get("bic"):
            pm.payee_institution.bic = p["bic"]
        doc.trade.settlement.payment_means.add(pm)

    # ── Summen ──
    ms = doc.trade.settlement.monetary_summation
    ms.line_total = D(p["net_total"])
    ms.charge_total = D(0)
    ms.allowance_total = D(0)
    ms.tax_basis_total = D(p["net_total"])
    ms.tax_total = (D(p["tax_total"]), "EUR")
    ms.grand_total = D(p["gross_total"])
    ms.due_amount = D(p["gross_total"])
    doc.trade.settlement.currency_code = p.get("currency", "EUR")

    # to_etree umgeht drafthorse's serialize-Validierung (deren XSDs hier
    # nicht gebündelt sind); die EN16931-CII-Struktur bleibt erhalten.
    return ET.tostring(doc.to_etree(), encoding="utf-8")


# ── #934: Extraktion — eingebettete CII-XML einer Eingangs-PDF lesen ────────
CII_NS = {
    "rsm": "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100",
    "ram": "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100",
    "udt": "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100",
}


def _t(node, path):
    el = node.find(path, CII_NS) if node is not None else None
    return el.text.strip() if el is not None and el.text else None


def _date(node, path):
    raw = _t(node, path + "/udt:DateTimeString")
    if raw and len(raw) >= 8:
        try:
            return datetime.strptime(raw[:8], "%Y%m%d").strftime("%Y-%m-%d")
        except ValueError:
            return None
    return None


def _num(node, path):
    raw = _t(node, path)
    try:
        return float(raw) if raw not in (None, "") else None
    except ValueError:
        return None


def _party(root, which):
    p = root.find(f".//ram:ApplicableHeaderTradeAgreement/ram:{which}TradeParty", CII_NS)
    if p is None:
        return None
    vat = None
    for tr in p.findall("ram:SpecifiedTaxRegistration/ram:ID", CII_NS):
        if tr.get("schemeID") == "VA" and tr.text:
            vat = tr.text.strip()
    return {
        "name": _t(p, "ram:Name"),
        "vat_id": vat,
        "line1": _t(p, "ram:PostalTradeAddress/ram:LineOne"),
        "postcode": _t(p, "ram:PostalTradeAddress/ram:PostcodeCode"),
        "city": _t(p, "ram:PostalTradeAddress/ram:CityName"),
        "country": _t(p, "ram:PostalTradeAddress/ram:CountryID"),
    }


def extract_from_pdf(pdf_path):
    from facturx import get_facturx_xml_from_pdf
    with open(pdf_path, "rb") as f:
        _name, xml_bytes = get_facturx_xml_from_pdf(f, check_xsd=False)
    if not xml_bytes:
        return None
    root = ET.fromstring(xml_bytes)

    lines = []
    for li in root.findall(".//ram:IncludedSupplyChainTradeLineItem", CII_NS):
        qty_el = li.find("ram:SpecifiedLineTradeDelivery/ram:BilledQuantity", CII_NS)
        lines.append({
            "description": _t(li, "ram:SpecifiedTradeProduct/ram:Name"),
            "quantity": _num(li, "ram:SpecifiedLineTradeDelivery/ram:BilledQuantity"),
            "unit": qty_el.get("unitCode") if qty_el is not None else None,
            "unit_price": _num(li, "ram:SpecifiedLineTradeAgreement/ram:NetPriceProductTradePrice/ram:ChargeAmount"),
            "tax_rate": _num(li, "ram:SpecifiedLineTradeSettlement/ram:ApplicableTradeTax/ram:RateApplicablePercent"),
            "net": _num(li, "ram:SpecifiedLineTradeSettlement/ram:SpecifiedLineTradeSettlementMonetarySummation/ram:LineTotalAmount"),
        })

    settlement = root.find(".//ram:ApplicableHeaderTradeSettlement", CII_NS)
    return {
        "number": _t(root, ".//rsm:ExchangedDocument/ram:ID"),
        "issue_date": _date(root, ".//rsm:ExchangedDocument/ram:IssueDateTime"),
        "seller": _party(root, "Seller"),
        "buyer": _party(root, "Buyer"),
        "lines": lines,
        "service_start": _date(settlement, "ram:BillingSpecifiedPeriod/ram:StartDateTime"),
        "service_end": _date(settlement, "ram:BillingSpecifiedPeriod/ram:EndDateTime"),
        "due_date": _date(settlement, "ram:SpecifiedTradePaymentTerms/ram:DueDateDateTime"),
        "payment_terms": _t(settlement, "ram:SpecifiedTradePaymentTerms/ram:Description"),
        "net_total": _num(settlement, "ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:LineTotalAmount"),
        "tax_total": _num(settlement, "ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount"),
        "gross_total": _num(settlement, "ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:GrandTotalAmount"),
        "iban": _t(settlement, "ram:SpecifiedTradeSettlementPaymentMeans/ram:PayeePartyCreditorFinancialAccount/ram:IBANID"),
        "currency": _t(settlement, "ram:InvoiceCurrencyCode"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["xml", "pdf", "extract"], required=True)
    ap.add_argument("--pdf")
    ap.add_argument("--out")
    args = ap.parse_args()

    if args.mode == "extract":
        try:
            data = extract_from_pdf(args.pdf)
        except Exception:
            data = None
        if data is None:
            sys.exit(3)  # keine eingebettete EN16931-XML
        json.dump(data, sys.stdout)
        return

    payload = json.load(sys.stdin)
    xml = build_xml(payload)

    if args.mode == "xml":
        sys.stdout.buffer.write(xml)
        return

    from facturx import generate_from_file
    with open(args.pdf, "rb") as f:
        pdf_in = io.BytesIO(f.read())
    generate_from_file(pdf_in, xml, flavor="factur-x", level="en16931",
                       check_xsd=False, output_pdf_file=args.out)


if __name__ == "__main__":
    main()
