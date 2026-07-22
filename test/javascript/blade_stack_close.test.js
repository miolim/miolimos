// #1091: Focus-Nachfolge beim Schliessen von Cards (Hans-Spec 2026-07-22).
// Laeuft ohne Build-Step/DOM: `node --test test/javascript/`.
// Die Cards sind hier schlicht Strings — die Regel kennt nur ihre
// Reihenfolge im Stack.
import { test } from "node:test"
import assert from "node:assert/strict"
import { focusTargetAfterClose } from "../../app/javascript/lib/blade_stack_close.js"

const STACK = ["a", "b", "c", "d"]

test("geschlossene Card hatte Focus → naechste Card rechts", () => {
  assert.equal(focusTargetAfterClose(STACK, ["b"], "b"), "c")
})

test("geschlossene Card hatte Focus, rechts ist nichts mehr → Card links", () => {
  assert.equal(focusTargetAfterClose(STACK, ["d"], "d"), "c")
})

test("geschlossene Card hatte NICHT den Focus → Focus bleibt (null)", () => {
  assert.equal(focusTargetAfterClose(STACK, ["b"], "d"), null)
  assert.equal(focusTargetAfterClose(STACK, ["d"], "a"), null)
})

test("ohne aktive Card wird nichts umgesetzt", () => {
  assert.equal(focusTargetAfterClose(STACK, ["b"], null), null)
})

test("Mehrfach-Close (#1032): Nachfolger rechts der letzten geschlossenen", () => {
  assert.equal(focusTargetAfterClose(STACK, ["b", "c"], "b"), "d")
  assert.equal(focusTargetAfterClose(STACK, ["b", "c"], "c"), "d")
})

test("Mehrfach-Close bis ans Stack-Ende faellt auf die Card links zurueck", () => {
  assert.equal(focusTargetAfterClose(STACK, ["b", "c", "d"], "c"), "a")
})

test("letzte Card des Stacks geschlossen → kein Ziel", () => {
  assert.equal(focusTargetAfterClose(["a"], ["a"], "a"), null)
  assert.equal(focusTargetAfterClose(STACK, STACK, "b"), null)
})

// ─── #1091 v2: End-Spacer-Mathematik ────────────────────────────────

import { endSpacerWidth, spacerWidthAfterScroll } from "../../app/javascript/lib/blade_stack_close.js"

test("endSpacerWidth: fehlende Breite bis zum rechten Viewport-Rand", () => {
  // Viewport 1000px, gescrollt auf 500 → Content muss bis 1500 reichen.
  // Nach dem Close nur noch 1200 → 300px Platzhalter.
  assert.equal(endSpacerWidth({ scrollLeft: 500, clientWidth: 1000, contentWidth: 1200 }), 300)
})

test("endSpacerWidth: genug Cards rechts → kein Platzhalter", () => {
  assert.equal(endSpacerWidth({ scrollLeft: 500, clientWidth: 1000, contentWidth: 2000 }), 0)
  assert.equal(endSpacerWidth({ scrollLeft: 500, clientWidth: 1000, contentWidth: 1500 }), 0)
})

test("endSpacerWidth: ungescrollter Stack schmaler als der Viewport → fuellt den Rest auf", () => {
  // scrollLeft 0: nachklemmen kann hier nichts (maxScroll bleibt 0), der
  // Spacer verhindert aber, dass beim Schliessen einer mittleren Card
  // Flex-Nachbarn den freigewordenen Platz anders verteilen.
  assert.equal(endSpacerWidth({ scrollLeft: 0, clientWidth: 1000, contentWidth: 800 }), 200)
})

test("spacerWidthAfterScroll: Links-Scrollen baut den Freiraum kontinuierlich ab", () => {
  assert.equal(spacerWidthAfterScroll(300, 500, 400), 200)   // 100 nach links → -100
  assert.equal(spacerWidthAfterScroll(200, 400, 390), 190)   // kleine Schritte, kein Snap
})

test("spacerWidthAfterScroll: Rechts-Scrollen laesst den Spacer stehen", () => {
  assert.equal(spacerWidthAfterScroll(300, 400, 500), 300)
})

test("spacerWidthAfterScroll: schrumpft nie unter 0", () => {
  assert.equal(spacerWidthAfterScroll(50, 500, 300), 0)
})
