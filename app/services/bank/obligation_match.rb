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

      # #1337 Schnitt 4: Nach dem Import die noch unentschiedenen Umsätze
      # zuordnen — aber NUR bei eindeutigem, betragsexaktem Treffer. Alles
      # andere (Teil-, Über-, Rückzahlung, Ausbuchung) bleibt Handarbeit: Eine
      # falsch verrechnete Zahlung fällt nicht auf.
      def auto(ledger)
        ledger.bank_transactions.unentschieden.count do |tx|
          o = kandidat_pflicht(tx)
          o.present? && assign(tx, o)
        end
      end

      # Die Gegenrichtung: Für eine gerade erfasste Zahlungspflicht den
      # passenden, noch nicht ausgeschöpften Umsatz suchen.
      def match_for_obligation(obligation)
        return false if obligation.blank? || obligation.settled?
        tx = kandidat_umsatz(obligation) or return false
        assign(tx, obligation)
      end

      # Wege, den Gegenpart eines Umsatzes zu bestimmen — VIER, nicht einer.
      #
      # immoos_builder aus dem Fork-Betrieb: „Bei SEPA-Lastschriften steht im
      # Auszug keine IBAN des Empfängers, sondern seine Gläubiger-ID. Wer den
      # Kreditor ausschließlich über hinterlegte Bankverbindungen sucht, findet
      # NIE etwas." Deshalb zusätzlich die Gläubiger-ID am Kontakt, der am
      # Umsatz verknüpfte Kontakt und der exakte Name.
      def gegenpart_uuids(tx)
        uuids = []
        uuids << tx.counterparty_knowledge_item_uuid if tx.counterparty_knowledge_item_uuid.present?
        uuids += ueber_bankverbindung(tx)
        uuids += ueber_glaeubiger_id(tx)
        uuids += ueber_namen(tx)
        uuids.compact.uniq
      end

      private

      def ueber_bankverbindung(tx)
        iban = tx.counterparty_iban.presence or return []
        BankAccount.where(iban: iban).distinct.pluck(:knowledge_item_uuid)
      end

      # Die Gläubiger-ID (Format DE..ZZZ…) steht im Verwendungszweck bzw. in der
      # Mandatsreferenz. Gesucht wird umgekehrt: Welche hinterlegte ID kommt in
      # diesem Umsatz vor? Kurze Werte bleiben außen vor — sie träfen zufällig.
      def ueber_glaeubiger_id(tx)
        text = [tx.purpose, tx.bank_ref, tx.counterparty_name].compact_blank.join(" ")
        return [] if text.blank?

        Identifier.where(label: "Gläubiger-Identifikationsnummer")
                  .where("LENGTH(value) >= 8 AND ? ILIKE '%' || value || '%'", text)
                  .distinct.pluck(:knowledge_item_uuid)
      end

      def ueber_namen(tx)
        name = tx.counterparty_name.presence or return []
        KnowledgeItem.persons_and_orgs.by_title_ci(name).pluck(:uuid)
      end

      # Eine eindeutige, betragsexakt passende offene Zahlungspflicht des
      # Gegenparts. Mehrdeutig heißt: nicht automatisch — lieber liegen lassen
      # als falsch verrechnen.
      def kandidat_pflicht(tx)
        uuids = gegenpart_uuids(tx)
        return nil if uuids.empty?

        # Bei einer Auszahlung ist der Gegenpart der Aussteller des fremden
        # Belegs; bei einer Einzahlung der Empfänger unseres eigenen.
        belege = tx.withdrawal? ? Invoice.eingehend.where(issuer_uuid: uuids)
                                : Invoice.ausgehend.where(recipient_uuid: uuids)
        treffer = PaymentObligation.where(bearer: belege).unsettled.to_a
                                   .select { |o| o.open_amount.abs == tx.restbetrag }
        treffer.length == 1 ? treffer.first : nil
      end

      def kandidat_umsatz(obligation)
        beleg = obligation.bearer
        return nil unless beleg.is_a?(Invoice)

        uuid = beleg.eingehend? ? beleg.issuer_uuid : beleg.recipient_uuid
        return nil if uuid.blank?

        offen = obligation.open_amount
        treffer = BankTransaction.unentschieden.to_a.select do |tx|
          tx.restbetrag == offen.abs && tx.amount.to_d.negative? == offen.negative? &&
            gegenpart_uuids(tx).include?(uuid)
        end
        treffer.length == 1 ? treffer.first : nil
      end

      def to_d(v) = v.is_a?(String) ? (Dezimalbetrag.parse(v) || BigDecimal("0")) : v.to_d
    end
  end
end
