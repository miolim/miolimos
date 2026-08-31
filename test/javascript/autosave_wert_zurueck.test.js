// #1496 (aus immoos #1457 R2 uebernommen): Darf der getippte Wert des Nutzers
// den des Servers ueberschreiben?
//
// Das ist die heikelste Zeile der ganzen Uebernahme. Wer sie zu grosszuegig
// macht, ueberschreibt eine Korrektur des Servers — der formatiert Betraege,
// fuellt abhaengige Felder, rechnet Summen nach — und der Nutzer sieht seinen
// halben Text statt der richtigen Antwort. Wer sie zu streng macht, verliert
// wieder das Getippte, und die ganze Uebung war umsonst.
//
// Laeuft ohne DOM: `node --test test/javascript/*.test.js`
import { test } from "node:test"
import assert from "node:assert/strict"
import { darfWertZurueck } from "../../app/javascript/lib/autosave_feedback.js"

// Ein Feld, wie es nach dem Austausch dasteht: `value` und `defaultValue`
// kommen beide vom Server.
const feld = (wert, geliefert = wert) => ({ value: wert, defaultValue: geliefert })
// Was vor dem Austausch gemerkt wurde.
const merk = (getippt, geliefert) => ({ wert: getippt, geliefert })

test("Lage 1: Server hat das Feld nicht angefasst — der Nutzer gewinnt", () => {
  // Vorher geliefert „Mül", jetzt liefert der Server wieder „Mül": Er hat
  // nichts geaendert, das Getippte ist das Neuere.
  assert.equal(darfWertZurueck(feld("Mül"), merk("Müller", "Mül")), true)
})

test("Lage 2: der Nutzer hat weitergetippt — der Nutzer gewinnt", () => {
  // Der Server hat „Mül" gespeichert und liefert es zurueck; inzwischen steht
  // „Müller" da. Sein Wert ist ein Anfang des getippten.
  assert.equal(darfWertZurueck(feld("Mül", "(anderer Stand)"), merk("Müller", "Mül")), true)
})

// Wichtig fuer das Verstaendnis — und beim ersten Anlauf hatte ich es selbst
// falsch: `feld.defaultValue` ist der Wert, den der Server JETZT gerendert
// hat, `merk.geliefert` der, den er VORHER gerendert hatte. Aendert der Server
// ein Feld, aendert sich also BEIDES: value und defaultValue. Meine ersten
// zwei Faelle liessen defaultValue auf dem alten Stand — damit sahen sie aus
// wie „Server hat nichts angefasst" und fielen prompt um. Der Code hatte
// recht, die Nachstellung nicht.
test("Lage 3: der Server hat wirklich etwas anderes gesetzt — der Server gewinnt", () => {
  // Formatierter Betrag: der Nutzer tippte „1234.5", der Server macht
  // „1.234,50" daraus und rendert genau das. Kein Anfang des Getippten —
  // seine Korrektur bleibt stehen.
  assert.equal(darfWertZurueck(feld("1.234,50", "1.234,50"), merk("1234.5", "0,00")), false)
})

test("ein aus der Kennung ergaenztes Feld bleibt beim Server", () => {
  // Der Klassiker: Aus der IBAN ergaenzt der Server BIC und Bankname. Das
  // Feld war leer, der Nutzer hat nichts getippt — es gibt nichts zu retten.
  assert.equal(darfWertZurueck(feld("GENODEF1S02", "GENODEF1S02"), merk("", "")), false)
})

test("steht der Wert schon da, wird nichts angefasst", () => {
  assert.equal(darfWertZurueck(feld("Müller"), merk("Müller", "Mül")), false)
})

test("Felder ohne defaultValue (SELECT u. a.) bleiben unberuehrt", () => {
  assert.equal(darfWertZurueck({ value: "a" }, merk("b", "a")), false)
})

test("ohne gemerkten Wert passiert nichts", () => {
  assert.equal(darfWertZurueck(feld("x"), merk(null, "x")), false)
  assert.equal(darfWertZurueck(feld("x"), null), false)
  assert.equal(darfWertZurueck(null, merk("y", "x")), false)
})

// Die Gegenprobe zur Lage 2: Ein Serverwert, der zufaellig laenger ist als das
// Getippte, darf nicht als „weitergetippt" durchgehen.
test("ein laengerer Serverwert ist kein Weitertippen", () => {
  assert.equal(darfWertZurueck(feld("Müllermann", "(anderer Stand)"), merk("Müller", "Mül")), false)
})
