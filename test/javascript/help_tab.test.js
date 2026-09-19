// immoOS #1658 Stufe 2: Der Hilfe-Schlüssel folgt dem offenen Reiter.
// Laeuft ohne DOM — die Card ist eine Attrappe mit querySelector.
import { test } from "node:test"
import assert from "node:assert/strict"
import { offenerReiter, hilfeSchluessel, hilfeBasis, hilfeTauschZiel } from "../../app/javascript/lib/help_tab.js"

// Baut eine Card-Attrappe: leiste = null heisst „Card ohne Reiter".
function card({ panelName, verschachtelt = false } = {}) {
  const panel = panelName === undefined ? null : { dataset: { name: panelName } }
  const leiste = {
    querySelector(auswahl) {
      // Nur die Direktkind-Abfrage liefert ein Panel; ein verschachtelter
      // Reiter wuerde ueber :scope > ... NICHT gefunden.
      if (!auswahl.startsWith(":scope >")) return null
      return verschachtelt ? null : panel
    }
  }
  return { querySelector: (auswahl) => (auswahl.includes("simple-tabs") ? leiste : null) }
}

test("offener Reiter wird aus dem sichtbaren Panel gelesen", () => {
  assert.equal(offenerReiter(card({ panelName: "settlement" })), "settlement")
})

test("Card ohne Reiter liefert keinen Reiter", () => {
  assert.equal(offenerReiter(card()), null)
  assert.equal(offenerReiter(null), null)
  assert.equal(offenerReiter(undefined), null)
})

test("Reiter in Reitern zaehlen nicht", () => {
  assert.equal(offenerReiter(card({ panelName: "heat", verschachtelt: true })), null)
})

test("unerlaubte Zeichen im Reiternamen werden verworfen", () => {
  assert.equal(offenerReiter(card({ panelName: "Ab.C!" })), null)
})

test("Schluessel bekommt den Reiter angehaengt", () => {
  assert.equal(hilfeSchluessel("property", "settlement"), "property.settlement")
  assert.equal(hilfeSchluessel("property", null), "property")
  // Ein schon zusammengesetzter Schluessel wird nicht doppelt gehaengt —
  // der zweite Klick darf nicht „property.details.settlement" bauen.
  assert.equal(hilfeSchluessel("property.details", "settlement"), "property.settlement")
  assert.equal(hilfeSchluessel("list:persons", null), "list:persons")
})

// ── #1665: die offene Hilfe folgt dem Reiter ──────────────────────────
test("Basis einer Hilfe-Stack-ID", () => {
  assert.equal(hilfeBasis("help:property.details"), "property")
  assert.equal(hilfeBasis("help:property"), "property")
  // Der Doppelpunkt gehoert zum Schluessel, der Punkt trennt den Reiter.
  assert.equal(hilfeBasis("help:list:properties"), "list:properties")
  assert.equal(hilfeBasis(null), "")
})

test("Reiterwechsel tauscht die offene Hilfe derselben Karte", () => {
  assert.equal(hilfeTauschZiel("property", "buildings", ["help:property.details"]),
               "help:property.buildings")
})

test("ohne offene Hilfe passiert nichts", () => {
  assert.equal(hilfeTauschZiel("property", "buildings", []), null)
  assert.equal(hilfeTauschZiel("property", "buildings", null), null)
  // Eine Hilfe zu einer ANDEREN Karte bleibt unangetastet.
  assert.equal(hilfeTauschZiel("property", "buildings", ["help:unit.details"]), null)
})

test("steht die richtige Hilfe schon da, wird nicht nachgeladen", () => {
  assert.equal(hilfeTauschZiel("property", "details", ["help:property.details"]), null)
  assert.equal(hilfeTauschZiel("list:properties", null, ["help:list:properties"]), null)
})

test("Karte ohne Reiter faellt auf den Karten-Schluessel zurueck", () => {
  assert.equal(hilfeTauschZiel("property", null, ["help:property.details"]), "help:property")
})

test("ohne Karten-Art passiert nichts", () => {
  assert.equal(hilfeTauschZiel(null, "details", ["help:property.details"]), null)
  assert.equal(hilfeTauschZiel("", "details", ["help:property.details"]), null)
})
