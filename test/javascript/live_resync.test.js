// #1653: Nach einer Verbindungsunterbrechung holt sich die Antwortenliste den
// Stand selbst. Geprüft wird die Entscheidung ohne DOM:
// `node --test test/javascript/`.
import { test } from "node:test"
import assert from "node:assert/strict"
import { istWiederverbunden, zaehlertext, pauseWarLang } from "../../app/javascript/lib/live_resync.js"

test("der erste Verbindungsaufbau ist keine Wiederverbindung", () => {
  assert.equal(istWiederverbunden(undefined, true), false,
               "sonst laedt jede frisch geoeffnete Card sofort ein zweites Mal")
  assert.equal(istWiederverbunden(null, true), false)
})

test("getrennt und wieder da = Wiederverbindung", () => {
  assert.equal(istWiederverbunden(false, true), true)
})

test("Trennen allein loest nichts aus", () => {
  assert.equal(istWiederverbunden(true, false), false)
  assert.equal(istWiederverbunden(false, false), false)
  assert.equal(istWiederverbunden(true, true), false)
})

test("der Zaehler bleibt leer, wenn es keine Antworten gibt", () => {
  assert.equal(zaehlertext(0), "")
  assert.equal(zaehlertext(""), "")
  assert.equal(zaehlertext(undefined), "")
  assert.equal(zaehlertext("3"), "· 3")
  assert.equal(zaehlertext(12), "· 12")
})

test("kurze Pausen im Hintergrund loesen kein Nachladen aus", () => {
  assert.equal(pauseWarLang(0), false)
  assert.equal(pauseWarLang(5000), false)
  assert.equal(pauseWarLang(20000), true)
  assert.equal(pauseWarLang(60000), true)
})
