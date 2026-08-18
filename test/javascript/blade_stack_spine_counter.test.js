// #1412: Position des Instanz-Zaehlers im Spine (Hans-Spec 2026-08-18).
// Laeuft ohne Build-Step/DOM: `node --test test/javascript/`.
//
// Die Regel: Der Zaehler sitzt an ZWEITER Stelle, unter dem Card-Icon —
// vorher sass er ganz oben und schob Icon und alles darunter nach unten.
import { test } from "node:test"
import assert from "node:assert/strict"
import { counterAnchorIndex } from "../../app/javascript/lib/blade_stack_spine.js"

// [Icon, Label, Schliessen] → hinter das Icon (Index 0)
test("normaler Spine: der Zaehler kommt hinter das Icon", () => {
  assert.equal(counterAnchorIndex([true, false, false]), 0)
})

// [Themenpunkt, Icon, Label] → hinter das Icon (Index 1), nicht hinter
// den Farbpunkt. Der Anker ist das Icon, nicht die feste Position.
test("Spine mit Themenfarb-Punkt: hinter das Icon, nicht hinter den Punkt", () => {
  assert.equal(counterAnchorIndex([false, true, false]), 1)
})

test("Spine ohne Icon: der Zaehler kommt nach vorn", () => {
  assert.equal(counterAnchorIndex([false, false]), -1)
  assert.equal(counterAnchorIndex([]), -1)
})

test("mehrere Icons: das ERSTE ist der Anker", () => {
  assert.equal(counterAnchorIndex([false, true, true, false]), 1)
})
