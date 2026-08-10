# #1337 Schnitt 1 (aus immoOS #975/#996/#1196/#1272): ein Bankkonto. Trägt
# seine Umsätze und die importierten Auszüge. Mehrere Konten möglich.
class BankLedger < ApplicationRecord
  has_many :bank_transactions, dependent: :destroy
  has_many :bank_statements,   dependent: :destroy

  # Konto einer Entität der aufsetzenden Anwendung (im Fork: Grundstück,
  # Gebäude, Einheit) — polymorph und optional. Bewusst `subject`, weil
  # `object` mit Object#object_id kollidiert.
  belongs_to :subject, polymorphic: true, optional: true

  validates :label, presence: true

  scope :ordered, -> { order(:label, :id) }

  before_save do
    self.iban = iban.to_s.gsub(/\s+/, "").upcase.presence
    self.bic  = bic.to_s.gsub(/\s+/, "").upcase.presence
  end

  # Saldo = Anfangssaldo (Bestandsübernahme) + Summe aller Umsätze.
  def balance = opening_balance.to_d + bank_transactions.sum(:amount)

  # Der Saldo gilt bis zur JÜNGSTEN Buchung, nicht bis heute. Liegt der letzte
  # Auszug drei Monate zurück, ist genau das die Auskunft, die fehlt. Ohne
  # Umsätze zählt der Stichtag des Anfangssaldos.
  def balance_on = bank_transactions.maximum(:booked_on) || opening_on

  def full_label = label.presence || iban

  # Der Fork hängt hier seine Entitäten an; upstream kann `subject` alles sein,
  # deshalb defensiv statt auf eine bestimmte Schnittstelle festgelegt.
  def subject_label
    return nil if subject.blank?
    %i[full_label title label name].filter_map { |m| subject.try(m).presence }.first
  end
end
