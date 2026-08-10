# #1337 Schnitt 1: Bankkonto, Auszug, Umsatz.
#
# Die Zahlungswelt wandert aus dem immoOS-Fork nach miolimOS — sie ist nicht
# hausverwaltungsspezifisch, sie lag dort nur historisch. Dieser Schnitt bringt
# die drei Entitäten, OHNE Importwege (Schnitt 3) und OHNE Ausgleich
# (Schnitt 2, setzt #1336 Stufe 2 voraus).
#
# Tabellen- und Spaltennamen sind der Fork-Stand `872befd0` — unverändert
# übernommen, wo sie tragen, damit der spätere Merge keine Schemakollision
# wird. Zwei bewusste Abweichungen, beide mit immoos_builder abgestimmt:
#
# 1. **`tenant_payment_id` fehlt.** Im Fork weiß der Umsatz, dass er eine
#    MIETERZAHLUNG tilgt — ein hausverwaltungsspezifischer Fremdschlüssel an
#    einer allgemeinen Entität. Richtig ist: Der Umsatz weiß, dass er *etwas*
#    tilgt; was, entscheidet die aufsetzende Anwendung. Die Zuordnung kommt in
#    Schnitt 2 als eigene Tabelle (`obligation_settlements`), wie beim
#    Ausgleich. Ohne diese Entkopplung nähme miolimOS ein Konzept mit, das
#    hier niemand braucht.
# 2. Der Ausgleich heißt später `obligation_settlements`, nicht
#    `invoice_settlements` — er tilgt eine Zahlungspflicht, keinen Beleg.
#
# `source` bleibt bewusst ein INTEGER-Enum, anders als die Belegart in #1336:
# Dort war die Liste offen und die Spalte leer; hier ist sie geschlossen und
# technisch (camt/csv/manual/pdf), und der Fork führt mehrere Jahre Umsätze
# darauf. Eine Umstellung auf Namen kostete ihn eine Datenwanderung ohne
# Gegenwert.
#
# Fünf Spalten, die im Fork erst nachträglich dazukamen und die er uns
# ausdrücklich mitgegeben hat — jede aus dem Betrieb, nicht aus dem Entwurf:
# `fingerprint` (Dublettenschutz je Konto — ein Auszug wird garantiert zweimal
# importiert), `bank_statement_id` (Herkunft; ohne sie ist eine fehlerhafte
# Einlieferung nicht mehr herauszulösen), `no_assignment_at`/`_note` (bewusst
# ohne Zuordnung: Darlehensrate, Kontoführungsentgelt, Umbuchung — ohne dieses
# Merkmal steht ein Drittel des Kontos für immer als „nicht zugeordnet" da),
# `counterparty_knowledge_item_uuid` (der Gegenpart als Verknüpfung, nicht als
# Name — ein Textfeld löst still auf nichts auf) und `source`.
class CreateBankEntities < ActiveRecord::Migration[8.0]
  def change
    create_table :bank_ledgers do |t|
      t.string  :label,      null: false
      t.string  :iban
      t.string  :bic
      t.string  :bank_name
      t.string  :holder
      t.string  :currency,   null: false, default: "EUR"
      # Konto einer Entität der aufsetzenden Anwendung — polymorph und
      # optional. Bewusst `subject` (nicht `object`, das kollidiert mit
      # Object#object_id).
      t.string  :subject_type
      t.bigint  :subject_id
      # Bestandsübernahme: Saldo = Anfangssaldo + Summe der Umsätze.
      t.decimal :opening_balance, precision: 12, scale: 2, null: false, default: 0
      t.date    :opening_on
      t.timestamps
    end
    add_index :bank_ledgers, [:subject_type, :subject_id]

    create_table :bank_statements do |t|
      t.references :bank_ledger, null: false, foreign_key: true
      t.string  :filename
      t.string  :format
      t.integer :entry_count,   null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.date    :period_from
      t.date    :period_to
      t.string  :source_path
      t.string  :note
      t.timestamps
    end

    create_table :bank_transactions do |t|
      t.references :bank_ledger,    null: false, foreign_key: true
      t.references :bank_statement, null: true,  foreign_key: true
      t.date    :booked_on
      t.date    :value_date
      # Vorzeichen wie beim Kontoauszug: positiv = Einzahlung, negativ =
      # Auszahlung. Dieselbe Konvention wie bei der Zahlungspflicht (#1336) —
      # nur so kann die Tilgung in Schnitt 2 ohne Fallunterscheidung prüfen.
      t.decimal :amount,   precision: 12, scale: 2, null: false
      t.string  :currency, null: false, default: "EUR"
      t.text    :purpose
      t.string  :counterparty_name
      t.string  :counterparty_iban
      t.string  :counterparty_knowledge_item_uuid
      t.string  :bank_ref
      t.string  :fingerprint, null: false
      t.integer :source,      null: false, default: 2   # manual
      t.datetime :no_assignment_at
      t.string   :no_assignment_note
      t.timestamps
    end
    add_index :bank_transactions, [:bank_ledger_id, :fingerprint], unique: true
    add_index :bank_transactions, :counterparty_knowledge_item_uuid,
              name: "idx_bank_tx_counterparty_ki"
  end
end
