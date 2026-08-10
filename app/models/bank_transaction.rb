# #1337 Schnitt 1 (aus immoOS #975/#1263/#1274/#1279/#1322): ein Bankumsatz.
#
# Vorzeichen wie auf dem Kontoauszug: positiv = Einzahlung, negativ =
# Auszahlung. Das ist dieselbe Konvention wie bei der Zahlungspflicht (#1336) —
# Geldrichtung aus eigener Sicht —, und nur deshalb kann die Tilgung in
# Schnitt 2 ohne Fallunterscheidung prüfen, ob Umsatz und Pflicht zueinander
# passen.
#
# Was hier bewusst FEHLT: `tenant_payment_id`. Im Fork weiß der Umsatz, dass er
# eine Mieterzahlung tilgt; das ist hausverwaltungsspezifisch und hat an einer
# allgemeinen Entität nichts zu suchen. Der Umsatz weiß, dass er *etwas* tilgt
# — was, entscheidet die aufsetzende Anwendung über die Tilgungstabelle aus
# Schnitt 2.
class BankTransaction < ApplicationRecord
  belongs_to :bank_ledger
  belongs_to :bank_statement, optional: true
  # #1337 Schnitt 2: die Tilgungen dieses Umsatzes. KEIN `dependent: :destroy` —
  # das Aufräumen läuft über `before_destroy`, damit der Zahlstatus der
  # betroffenen Pflichten NACH dem Entfernen der Zuordnungen neu berechnet wird
  # und nicht auf einem Stand von vorher stehenbleibt.
  has_many :obligation_settlements

  # Woher der Umsatz kam. Beim PDF-Weg ist das die Voraussetzung dafür,
  # überhaupt misstrauisch sein zu können (ein Handyfoto ist kein Importweg —
  # die Texterkennung hat im Fork eine vollständige Buchungszeile verloren).
  #
  # Anders als die Belegart in #1336 bleibt das ein Integer-Enum: Die Liste ist
  # geschlossen und technisch, und der Fork führt mehrere Jahre Umsätze darauf.
  enum :source, { camt: 0, csv: 1, manual: 2, pdf: 3 }, default: :manual

  validates :amount, presence: true, numericality: true
  validates :fingerprint, presence: true, uniqueness: { scope: :bank_ledger_id }

  before_validation :set_default_fingerprint, on: :create

  # Zuordnungen lösen, BEVOR die Zeilen mit dem Umsatz verschwinden — sonst
  # bleibt der Zahlstatus der betroffenen Pflichten auf einem Stand von vorher.
  before_destroy { Bank::ObligationMatch.unassign(self) if obligation_settlements.exists? }

  scope :ordered, -> { order(booked_on: :desc, id: :desc) }

  # Braucht dieser Umsatz noch eine Entscheidung? Maßgeblich ist NICHT „hat
  # eine Zuordnung", sondern „ist er ausgeschöpft" — eine Sammelüberweisung
  # zahlt mehrere Pflichten, und die zweite kam im Fork nie an ihn heran.
  scope :unentschieden, lambda {
    where(no_assignment_at: nil).where(<<~SQL.squish)
      ABS(bank_transactions.amount) > COALESCE((
        SELECT ABS(SUM(os.amount)) FROM obligation_settlements os
        WHERE os.bank_transaction_id = bank_transactions.id
      ), 0)
    SQL
  }

  # Ein Suchschlitz für Begriffe UND Beträge: Sieht die Eingabe wie ein Betrag
  # aus, wird zusätzlich danach gesucht — mit und ohne Vorzeichen, denn ob eine
  # Zahlung als +500 oder −500 im Konto steht, weiß man beim Suchen selten.
  scope :suche, lambda { |q|
    text = q.to_s.strip
    next all if text.blank?

    muster = "%#{text.downcase}%"
    treffer = where("LOWER(purpose) LIKE :m OR LOWER(counterparty_name) LIKE :m OR " \
                    "LOWER(counterparty_iban) LIKE :m OR LOWER(bank_ref) LIKE :m", m: muster)
    betrag = Dezimalbetrag.parse(text)
    betrag.present? ? treffer.or(where(amount: [betrag.abs, -betrag.abs])) : treffer
  }

  def deposit?    = amount.to_d.positive?
  def withdrawal? = amount.to_d.negative?

  # Bewusst ohne Zuordnung — Darlehensrate, Kontoführungsentgelt, Umbuchung
  # zwischen eigenen Konten. Der Umsatz ist damit erledigt, ohne dass es einen
  # Beleg gäbe. Ohne dieses Merkmal steht ein Drittel des Kontos für immer als
  # „nicht zugeordnet" da, und die Liste wird wertlos.
  def no_assignment? = no_assignment_at.present?

  def mark_no_assignment!(note = nil)
    update!(no_assignment_at: Time.current, no_assignment_note: note.presence)
  end

  def clear_no_assignment! = update!(no_assignment_at: nil, no_assignment_note: nil)

  # Was von diesem Umsatz noch verteilt werden kann.
  #
  # Ein Umsatz ist NICHT erledigt, sobald er einmal zugeordnet ist, sondern
  # erst, wenn er ausgeschöpft ist: Eine Sammelüberweisung über 1.450,21 €
  # zahlt zwei Rechnungen.
  def zugeordneter_betrag = obligation_settlements.sum(:amount).to_d.abs

  # Nie negativ: Ist mehr zugeordnet als da ist, bleibt nichts übrig — dann ist
  # die Zuordnung falsch, nicht der Rest.
  def restbetrag  = [amount.to_d.abs - zugeordneter_betrag, 0].max
  def rest_offen? = restbetrag.positive?

  private

  # Dublettenschutz je Konto. Eine eindeutige Bank-Referenz ist der beste
  # Fingerprint; sonst ein Hash der Kernfelder.
  #
  # Die laufende Nummer für MEHRERE identische Umsätze innerhalb eines Auszugs
  # gehört in den Importer (Schnitt 3) und nicht hierher: Sie muss über den
  # ganzen Auszug hinweg deterministisch vergeben werden, damit ein erneuter
  # Import derselben Datei dieselben Fingerprints erzeugt und alle Zeilen als
  # Duplikat erkannt werden. Vergäbe das Modell hier „die nächste freie
  # Nummer", liefe genau dieser Schutz leer.
  def set_default_fingerprint
    return if fingerprint.present?
    self.fingerprint =
      if bank_ref.present?
        "ref:#{bank_ref}"
      else
        Digest::SHA256.hexdigest(
          [bank_ledger_id, booked_on, amount.to_s, purpose,
           counterparty_iban, counterparty_name].join("|")
        )
      end
  end
end
