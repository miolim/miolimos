# #1337 Schnitt 2 (aus immoOS #1017/#1021/#1322): Bankumsatz ↔ Zahlungspflicht
# zuordnen — der offene-Posten-Ausgleich.
#
# Im Fork heißt das Gegenstück `Bank::InvoiceMatch` und tilgt einen BELEG. Das
# geht nicht mehr: Ein Beleg mit vier Quartalsraten lässt nicht erkennen,
# welche Rate ein Umsatz getilgt hat. Getilgt wird deshalb die Zahlungspflicht.
#
# Teil-, Über- und Rückzahlung sowie die Ausbuchung laufen bewusst VON HAND.
# Eine falsch verrechnete Zahlung fällt nicht auf — automatisch zugeordnet wird
# nur bei eindeutigem, betragsexaktem Treffer, und das erst in Schnitt 4.
module Bank
  class ObligationMatch
    class << self
      # Einen Umsatz einer Zahlungspflicht zuordnen.
      #
      # `amount` optional (Teilbetrag, ohne Vorzeichen). Das Vorzeichen ergibt
      # sich aus dem Umsatz — Geldrichtung aus eigener Sicht, dieselbe
      # Konvention wie bei der Pflicht. Ohne Angabe wird so viel zugeordnet, wie
      # beide noch hergeben: der kleinere der beiden Reste.
      def assign(tx, obligation, amount = nil)
        return false unless tx && obligation
        return false if ObligationSettlement.exists?(payment_obligation_id: obligation.id,
                                                     bank_transaction_id: tx.id)

        moeglich = [tx.restbetrag, obligation.open_amount.abs].min
        betrag   = amount.present? ? to_d(amount).abs : moeglich
        betrag   = moeglich if betrag > moeglich
        return false if betrag.zero?

        ObligationSettlement.create!(
          payment_obligation: obligation, bank_transaction: tx, kind: :zahlung,
          amount: tx.withdrawal? ? -betrag : betrag,
          settled_on: tx.booked_on || Date.current
        )
        true
      end

      # Alle Zuordnungen eines Umsatzes lösen. Die betroffenen Pflichten (und
      # über sie die Belege) bewerten sich danach neu.
      def unassign(tx)
        tx.obligation_settlements.destroy_all
      end

      # Eine einzelne Zuordnung lösen.
      def unassign_settlement(settlement) = settlement.destroy

      # Restbetrag einer Pflicht ohne Umsatz abschreiben (Differenzausbuchung):
      # Das Geld kommt nicht mehr. `on` bestimmt, in welchem Jahr die
      # Ausbuchung zählt — bei Abflussprinzip ist das keine Kleinigkeit.
      def write_off(obligation, note: nil, on: nil)
        rest = obligation.open_amount
        return false if rest.zero?
        ObligationSettlement.create!(payment_obligation: obligation, kind: :ausbuchung,
                                     amount: rest, note: note.presence,
                                     settled_on: on || Date.current)
        true
      end

      private

      def to_d(v) = v.is_a?(String) ? (Dezimalbetrag.parse(v) || BigDecimal("0")) : v.to_d
    end
  end
end
