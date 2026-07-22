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

import { endSpacerWidth } from "../../app/javascript/lib/blade_stack_close.js"

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

// #1091 v3 (Hans): KEIN Abbau des Spacers beim Scrollen mehr — der
// Freiraum ist begehbar (rein/raus scrollen erlaubt) und schrumpft nur,
// wenn neue Cards ihn fuellen. spacerWidthAfterScroll ist entfernt.

// ─── #1091 v4: Stehender Overscroll + Regal-Schritte ────────────────

import { standingSpacerWidth, nextShelfStop, prevShelfStop } from "../../app/javascript/lib/blade_stack_close.js"

test("standingSpacerWidth: breiter Viewport → Overscroll bis zur Voll-Regal-Position", () => {
  // 4 Cards à 576, letzte bei X=1728, sticky-Pin bei 3*28=84.
  // Voll-Regal-Scroll = 1728-84 = 1644; Content 2312 → 1644+1942-2312 = 1274.
  assert.equal(
    standingSpacerWidth({ clientWidth: 1942, contentWidth: 2312, lastCardX: 1728, lastStickyLeft: 84 }),
    1274
  )
})

test("standingSpacerWidth: schmaler Viewport → natuerliches Ende IST schon Voll-Regal", () => {
  // Letzte Card geclampt auf cw-cardW: 706-576=130 → 1728-130+706-2312 < 0 → 0.
  assert.equal(
    standingSpacerWidth({ clientWidth: 706, contentWidth: 2312, lastCardX: 1728, lastStickyLeft: 130 }),
    0
  )
})

test("nextShelfStop: naechster Stop rechts der aktuellen Position", () => {
  const stops = [0, 548, 1096, 1644]
  assert.equal(nextShelfStop(stops, 0), 548)
  assert.equal(nextShelfStop(stops, 600), 1096)
  assert.equal(nextShelfStop(stops, 1644), null)   // Voll-Regal erreicht
})

test("prevShelfStop: naechster Stop links der aktuellen Position", () => {
  const stops = [0, 548, 1096, 1644]
  assert.equal(prevShelfStop(stops, 1644), 1096)
  assert.equal(prevShelfStop(stops, 600), 548)
  assert.equal(prevShelfStop(stops, 0), null)
})

test("Shelf-Stops sind toleranzbehaftet (±1px zaehlt nicht als eigener Stop)", () => {
  const stops = [0, 548]
  assert.equal(nextShelfStop(stops, 547.5), null)
  assert.equal(prevShelfStop(stops, 0.5), null)
})
