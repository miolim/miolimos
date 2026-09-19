// immoOS #1661: Die beiden Anlege-Zeilen stehen in zwei Auswahlfeldern
// (Einzelauswahl im Formular, Mehrfachauswahl der Zahlungsregel). Wann sie
// erscheinen, entscheidet eine Stelle — hier ist sie geprüft.
import { test } from "node:test"
import assert from "node:assert/strict"
import { anlegeEintraege } from "../../app/javascript/lib/person_anlegen.js"

const treffer = [{ uuid: "a", label: "Emma Roth" }]

test("ab zwei Zeichen stehen beide Arten zur Wahl", () => {
  const zeilen = anlegeEintraege("Em", [], ["person", "organization"])
  assert.deepEqual(zeilen.map((z) => z._create), ["person", "organization"])
  assert.equal(zeilen[0].label, "Em")
})

test("ein Zeichen reicht nicht — sonst blitzt die Zeile beim Tippen auf", () => {
  assert.deepEqual(anlegeEintraege("E", [], ["person"]), [])
})

// Der Kern: Die Suche steht VOR dem Anlegen (Hans, #1661).
test("wer schon existiert, wird nicht noch einmal angelegt", () => {
  assert.deepEqual(anlegeEintraege("Emma Roth", treffer, ["person"]), [])
  assert.deepEqual(anlegeEintraege("emma roth", treffer, ["person"]), [],
                   "Groß-/Kleinschreibung macht keinen zweiten Menschen")
})

test("ein Teiltreffer verbirgt das Anlegen nicht", () => {
  const zeilen = anlegeEintraege("Emma Rothmann", treffer, ["person"])
  assert.equal(zeilen.length, 1)
  assert.equal(zeilen[0].label, "Emma Rothmann")
})

test("die Stelle bestimmt die Reihenfolge — Versorger sind Organisationen", () => {
  const zeilen = anlegeEintraege("Stadtwerke", [], ["organization", "person"])
  assert.equal(zeilen[0]._create, "organization")
})

test("ohne Vorgabe gelten beide Arten", () => {
  assert.deepEqual(anlegeEintraege("Neu", [], null).map((z) => z._create),
                   ["person", "organization"])
})
