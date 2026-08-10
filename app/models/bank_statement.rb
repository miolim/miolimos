# #1337 Schnitt 1 (aus immoOS #1014): ein importierter Kontoauszug. Hält die
# daraus NEU angelegten Umsätze — ohne diese Herkunft ist eine fehlerhafte
# Einlieferung nicht mehr herauszulösen.
#
# Die Importwege (CAMT, CSV, PDF mit Saldo-Prüfsumme) kommen in Schnitt 3; hier
# steht nur die Entität, damit Schnitt 3 keine Migration mehr braucht.
class BankStatement < ApplicationRecord
  belongs_to :bank_ledger
  has_many :bank_transactions, dependent: :destroy

  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  def label = filename.presence || "#{format.to_s.upcase}-Import"

  # Zeitraum der enthaltenen Buchungen (aus den gespeicherten Grenzen).
  def period
    return nil unless period_from || period_to
    [period_from, period_to].compact.map { |d| I18n.l(d, format: :default) }.uniq.join(" – ")
  end

  # Import rückgängig: die Umsätze dieses Auszugs verschwinden mit ihm.
  #
  # Im Fork löst `revert!` vorher die erzeugten Miet-Zahlungen und die
  # Rechnungs-Zuordnungen. Beides gibt es hier (noch) nicht — die Tilgung kommt
  # in Schnitt 2. Wird sie ergänzt, gehört das Lösen der Zuordnungen VOR das
  # Löschen, damit der Zahlstatus der Zahlungspflichten danach neu berechnet
  # wird und nicht auf einem Stand von vorher stehenbleibt.
  def revert! = destroy!
end
