// #1677 (aus immoOS 6ad257b6 uebernommen): Ein Klick auf einen Vorschlag darf nie die falsche Person
// wählen — auch nicht, wenn zwischendurch eine neue Suchantwort eintrifft
// oder die Liste geschlossen wurde.
import { test } from "node:test"
import assert from "node:assert/strict"
import { sichtbaresItem } from "../../app/javascript/lib/autocomplete_auswahl.js"

const gerendert = [{ uuid: "a", title: "Anna" }, { uuid: "b", title: "Bernd" }]

test("gewaehlt wird, was der Nutzer sieht", () => {
  assert.equal(sichtbaresItem(gerendert, gerendert, 1).uuid, "b")
})

// Der Kern: neue Antwort im Hintergrund, alter Klick im Vordergrund.
test("eine neue Suchantwort verschiebt die Auswahl nicht", () => {
  const neu = [{ uuid: "z", title: "Zora" }]
  assert.equal(sichtbaresItem(gerendert, neu, 1).uuid, "b")
})

// Der Blur-Timer schliesst die Liste, bevor mousedown verarbeitet ist.
test("nach dem Schliessen gilt die gerenderte Liste weiter", () => {
  assert.equal(sichtbaresItem(gerendert, [], 0).uuid, "a")
})

test("ohne gerenderte Liste zaehlt der aktuelle Stand", () => {
  assert.equal(sichtbaresItem([], gerendert, 0).uuid, "a")
  assert.equal(sichtbaresItem(undefined, gerendert, 1).uuid, "b")
})

test("unbrauchbare Position liefert nichts", () => {
  assert.equal(sichtbaresItem(gerendert, gerendert, 9), undefined)
  assert.equal(sichtbaresItem(gerendert, gerendert, -1), undefined)
  assert.equal(sichtbaresItem(gerendert, gerendert, NaN), undefined)
})
