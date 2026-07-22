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
