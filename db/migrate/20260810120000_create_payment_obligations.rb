# #1336 Stufe 2: Zahlungspflicht als eigener Bestandteil.
#
# Der Beleg ist Nachweis, nicht Wirkung. Was er bewirkt, hängt an ihm —
# 0..n Zahlungspflichten je Beleg. Damit wird abbildbar, was `invoices.due_date`
# nicht konnte: ein Grundsteuerbescheid mit vier Quartalsraten, ein
# Versicherungsschein mit Raten — und, wichtiger, ein Beleg GANZ OHNE
# Zahlungspflicht (Festsetzungsbescheid, Vertrag, Kontoauszug), der dann auch
# nicht mehr als offener Posten erscheinen kann.
#
# ── Entwurfsentscheidungen (Hans/immoos_builder in #1336) ────────────────
#
# `bearer` (polymorph, Pflicht) — WEM die Pflicht gehört: das dauerhafte
# Zahlungsverhältnis, wenn es eines gibt, sonst der Beleg selbst. In miolimOS
# gibt es heute nur den Beleg; der Fork hängt hier seine Verträge an.
#
# `announced_by` (Beleg, optional) — WORAUF sie steht. Beides zusammen löst
# das „0 gegen 4" der Fallsammlung ohne ein Unterscheidungsmerkmal am Beleg:
# Der Abwasserbescheid erzeugt zwei Pflichten mit Träger Vertrag, angekündigt
# durch diesen Bescheid — sie gehören ihm nicht, werden aber auch nicht
# unterschlagen. Der Grundsteuerbescheid erzeugt vier mit Träger Beleg, weil
# es kein Verhältnis gibt, das sie führen könnte.
#
# `amount` ist VORZEICHENBEHAFTET, und zwar als Geldrichtung aus eigener
# Sicht — nicht als „Forderung gegen Gutschrift". Damit gilt die Invariante
# Vorzeichen der Pflicht = Vorzeichen des tilgenden Umsatzes, und die
# Tilgungslogik kommt später ohne Fallunterscheidung aus. Im Fork hat die
# umgekehrte Wahl ein vollständig erstattetes Guthaben lautlos aus der
# Betriebskostenabrechnung fallen lassen (#1329).
#
# `settled_amount` ist eine nachgeführte Ableitungsspalte, KEIN Fremdschlüssel
# auf einen Umsatz. Solange es upstream keine Umsätze gibt, schreibt die
# Oberfläche sie direkt (Häkchen „bezahlt" = voll getilgt); mit #1337 wird
# dieselbe Spalte aus der Tilgungstabelle nachgeführt. Der Fork hat den
# 1:1-Fremdschlüssel zweimal gebaut und zweimal ersetzen müssen (#1017/#1021)
# — deshalb hier von Anfang an ein Betrag, kein Verweis: eine Pflicht kann
# damit auch teilweise getilgt sein.
class CreatePaymentObligations < ActiveRecord::Migration[8.0]
  def up
    create_table :payment_obligations do |t|
      t.string  :bearer_type,     null: false
      t.bigint  :bearer_id,       null: false
      t.bigint  :announced_by_id, null: true
      t.decimal :amount,          precision: 12, scale: 2, null: false, default: 0
      t.decimal :settled_amount,  precision: 12, scale: 2, null: false, default: 0
      t.date    :due_on
      t.string  :label
      t.integer :position,        null: false, default: 0
      t.timestamps
    end
    add_index :payment_obligations, [:bearer_type, :bearer_id]
    add_index :payment_obligations, :announced_by_id
    add_index :payment_obligations, :due_on
    add_foreign_key :payment_obligations, :invoices, column: :announced_by_id, on_delete: :nullify

    # ── Bestandswanderung, verlustfrei ────────────────────────────────────
    # Jeder Beleg MIT Fälligkeit bekommt genau eine Zahlungspflicht; Belege
    # ohne Fälligkeit bekommen keine. Der Betrag ist der Bruttobetrag aus den
    # Positionen, mit dem Vorzeichen der Geldrichtung. War der Beleg als
    # bezahlt geführt, gilt die Pflicht als voll getilgt.
    say_with_time "Bestandsbelege → Zahlungspflichten" do
      rows = select_all(<<~SQL.squish)
        SELECT i.id, i.due_date, i.payment_status, i.direction,
               COALESCE((SELECT SUM(l.quantity * l.unit_price * (1 + l.tax_rate / 100.0))
                         FROM invoice_lines l WHERE l.invoice_id = i.id), 0) AS gross
        FROM invoices i
        WHERE i.due_date IS NOT NULL
      SQL
      rows.each do |r|
        gross  = r["gross"].to_d.round(2)
        # direction: 0 = ausgehend (Geld kommt zu uns), 1 = eingehend (Geld geht weg)
        amount = r["direction"].to_i == 1 ? -gross : gross
        # payment_status: 0 = offen, 1 = bezahlt
        settled = r["payment_status"].to_i == 1 ? amount : 0
        execute(<<~SQL.squish)
          INSERT INTO payment_obligations
            (bearer_type, bearer_id, announced_by_id, amount, settled_amount,
             due_on, position, created_at, updated_at)
          VALUES
            ('Invoice', #{r['id'].to_i}, #{r['id'].to_i}, #{amount}, #{settled},
             '#{r['due_date']}', 0, NOW(), NOW())
        SQL
      end
      rows.count
    end
  end

  def down
    drop_table :payment_obligations
  end
end
