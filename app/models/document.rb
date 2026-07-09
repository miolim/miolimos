# #532 (Hans, 2026-06-08) / #926 (2026-07-09): Document = das ANSCHREIBEN —
# Empfänger + Briefkopf + Freitext (Body-KI, erbt Editor/Versionierung/
# Wikilinks). Rechnung/Angebot sind seit #926 eine eigene Entität (Invoice);
# das gemeinsame Erstellungs-Verfahren (Parteien, Infoblock, Artefakte,
# Sperre, Render) liegt im Printable-Concern + DocumentRenderer.
# NDA und SEPA-Lastschriftmandat bleiben Spielarten des Anschreibens
# (Prosa/Formular ohne eigene Datenstruktur).
class Document < ApplicationRecord
  # #602 S1: sichtbar = eigene Dokumente + Dokumente sichtbarer Topics.
  include VisibleVia
  visible_via topic_column: :topic_id
  include Printable

  # #926: rechnung(2)/angebot(3) sind zur Invoice-Entität ausgezogen; die
  # Werte bleiben reserviert (alte Rows sind per Migration entsorgt).
  enum :kind, { brief: 0, nda: 1, lastschrift: 4 }   # #786: SEPA-Lastschriftmandat

  belongs_to :body_ki, class_name: "KnowledgeItem", foreign_key: :body_ki_uuid,
                       primary_key: :uuid, optional: true
  # #786 Inkr.2: gewählte Bankverbindung des Schuldners (= Aussteller) fürs
  # SEPA-Mandat. Optional; nil → automatisch die erste Bankverbindung.
  belongs_to :debtor_bank_account, class_name: "BankAccount", optional: true

  validates :kind, presence: true

  # #786 Inkr.2: die fürs Mandat genutzte Bankverbindung des Schuldners
  # (= Aussteller). Gewählte, falls sie zum aktuellen Aussteller gehört;
  # sonst automatisch die erste Bankverbindung des Ausstellers.
  def effective_debtor_account
    chosen = debtor_bank_account if debtor_bank_account && debtor_bank_account.knowledge_item_uuid == issuer_uuid
    chosen || issuer&.bank_accounts&.ordered&.first
  end

  # Anrede: Override-Feld, sonst ein konservativer Default (Geschlecht/Titel
  # führen wir am KI noch nicht, daher neutral + pro Dokument überschreibbar).
  def salutation_line
    return salutation if salutation.present?
    "Sehr geehrte Damen und Herren"
  end

  # #562 (Hans): Dokument-ID für die NDA-Fußzeile: [YYYY-MM-DD-hh-mm]_[Kunde]_NDA.
  # Zeitstempel = Anlage des Dokuments (stabil je Dokument); Kunde = Empfänger,
  # dateinamenssicher (Leerraum→-, sonst nur Wort-/Bindezeichen).
  def pdf_doc_id
    stamp = (created_at || Time.current).strftime("%Y-%m-%d-%H-%M")
    kunde = recipient&.title.to_s.strip.gsub(/\s+/, "-").gsub(/[^\p{Alnum}\-_]/u, "")
    kunde = "Kunde" if kunde.blank?
    "#{stamp}_#{kunde}_NDA"
  end

  # #559 (Hans): Benennung des Dokuments = sein Betreff. nil, wenn leer.
  def display_name = subject.presence

  # #562: die NDA rendert mehrseitig mit Fußzeile (Seitenzahl + Dokument-ID).
  def print_paged? = nda?
  def print_doc_id = pdf_doc_id

  # #926 Stufe 2: Anschreiben-spezifische Merge-Schlüssel.
  def merge_context
    super.merge({ "betreff" => subject.presence, "anrede" => salutation_line }.compact)
  end
end
