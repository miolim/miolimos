// #1167: Sticky-Offset-Mathematik des Card-Stapels.
// Laeuft ohne Build-Step/DOM: `node --test test/javascript/`.
import { test } from "node:test"
import assert from "node:assert/strict"
import { stickyOffsets, SPINE_STEP_MIN } from "../../app/javascript/lib/blade_stack_sticky.js"

const STEP = 28

test("wenige Cards: unveraenderte 28px-Schritte, Rights wie bisher", () => {
  const { step, offsets } = stickyOffsets({
    widths: [700, 576, 576], clientWidth: 1600, step: STEP
  })
  assert.equal(step, STEP)
  assert.deepEqual(offsets.map(o => o.left), [0, 28, 56])
  assert.deepEqual(offsets.map(o => o.right), [3 * 28 - 700, 2 * 28 - 576, 1 * 28 - 576])
  assert.deepEqual(offsets.map(o => o.zIndex), [0, 1, 2])
})

test("letzte Card wird geklemmt, wenn ihr Pin-Platz sie aus dem Viewport schieben wuerde (#281)", () => {
  // 33 Cards à 576 in 700px: selbst mit minStep (4px) liegt der
  // natuerliche Pin-Platz der letzten Card (32*4=128) rechts von
  // 700-576=124 → Klemmung greift.
  const widths = Array(33).fill(576)
  const { offsets } = stickyOffsets({ widths, clientWidth: 700, step: STEP })
  assert.equal(offsets[32].left, 700 - 576)
  // Vorletzte behaelt ihren (geschrumpften) Stapel-Platz.
  assert.ok(offsets[31].left <= offsets[32].left + STEP)
})

test("viele Cards: Schritt schrumpft, damit Stapel + breiteste Card in den Container passen", () => {
  // 33 Cards à 576 in 706px (Live-Repro aus #1167): fester 28er-Schritt
  // ergaebe 896px linken Stapel — breiter als der Container.
  const widths = Array(33).fill(576)
  const { step, offsets } = stickyOffsets({ widths, clientWidth: 706, step: STEP })
  assert.ok(step < STEP)
  const pile = 32 * step
  assert.ok(pile + 576 <= 706 + 32 * SPINE_STEP_MIN,
    `Stapel (${pile}px) muss neben der Card Platz finden`)
  // Kein Pin-Platz einer Vorgaenger-Card liegt rechts der geklemmten
  // letzten Card — genau das verdeckte vorher die Spines.
  const lastLeft = offsets[32].left
  for (let i = 0; i < 32; i++) {
    assert.ok(offsets[i].left <= lastLeft + 1,
      `Card ${i} pint bei ${offsets[i].left}px, letzte Card bei ${lastLeft}px`)
  }
})

test("aeusserste rechte Card dockt mit vollem step-Slot an, tiefere Plaetze schrumpfen (#1167 v2)", () => {
  const widths = Array(33).fill(576)
  const cw = 706
  const { step, offsets } = stickyOffsets({ widths, clientWidth: cw, step: STEP })
  // Letzte Card: Andock-Platz = voller SPINE_STEP → 28px Ruecken sichtbar.
  assert.equal(offsets[32].right, STEP - 576)
  const pinLeftEdge = (i) => cw - (offsets[i].right + 576)
  assert.equal(pinLeftEdge(32), cw - STEP)
  // Vorletzte dockt einen (geschrumpften) Schritt links davon an.
  assert.equal(Math.round(pinLeftEdge(31)), Math.round(cw - STEP - step))
})

test("Schritt faellt nie unter minStep", () => {
  const widths = Array(200).fill(576)
  const { step } = stickyOffsets({ widths, clientWidth: 700, step: STEP })
  assert.equal(step, SPINE_STEP_MIN)
})

test("einzelne Card: voller Schritt, keine Klemmung noetig", () => {
  const { step, offsets } = stickyOffsets({ widths: [576], clientWidth: 1000, step: STEP })
  assert.equal(step, STEP)
  assert.deepEqual(offsets, [{ left: 0, right: STEP - 576, zIndex: 0 }])
})

test("leerer Stack", () => {
  assert.deepEqual(stickyOffsets({ widths: [], clientWidth: 1000, step: STEP }).offsets, [])
})

test("Card breiter als der Container: Klemmung auf 0, kein negativer Left", () => {
  const { offsets } = stickyOffsets({ widths: [400, 960], clientWidth: 706, step: STEP })
  assert.equal(offsets[1].left, 0)
})
