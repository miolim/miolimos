// #1228: Ueberstand breiter Cards im Regal-Zustand.
// Laeuft ohne Build-Step/DOM: `node --test test/javascript/`.
import { test } from "node:test"
import assert from "node:assert/strict"
import { overhangClips } from "../../app/javascript/lib/blade_stack_overhang.js"

test("Cards nebeneinander ohne Ueberlappung werden nicht geclippt", () => {
  const rects = [
    { left: 0,   right: 600 },
    { left: 600, right: 1200 },
    { left: 1200, right: 1800 }
  ]
  assert.deepEqual(overhangClips(rects), [0, 0, 0])
})

test("Regal-Zustand: jede Card endet an der Kante ihrer Nachfolgerin", () => {
  // Drei Cards kleben links im Abstand von 4px (geschrumpfter Schritt).
  const rects = [
    { left: 65, right: 737 },
    { left: 69, right: 969 },
    { left: 73, right: 649 }
  ]
  // Card 0 bis zur Kante von Card 1 (69), Card 1 bis zur Kante von Card 2 (73).
  assert.deepEqual(overhangClips(rects), [737 - 69, 969 - 73, 0])
})

test("die vorderste Card wird nie geclippt", () => {
  const rects = [{ left: 0, right: 900 }, { left: 210, right: 590 }]
  assert.equal(overhangClips(rects).at(-1), 0)
})

// Der eigentliche Fehlerfall: eine breite Card hinter einer schmalen.
// Ohne Clip bliebe rechts der schmalen Card ein Streifen der breiten stehen.
test("breite Card hinter schmaler ragt nicht mehr rechts heraus", () => {
  const rects = [
    { left: 69,  right: 969 },   // breit, liegt hinten
    { left: 210, right: 590 }    // schmal, liegt vorn und deckt nur bis 590
  ]
  const [clip] = overhangClips(rects)
  assert.equal(clip, 969 - 210, "muss ab der Kante der vorderen Card abschneiden")
  assert.equal(969 - clip, 210, "sichtbar bleibt nur der Teil links der vorderen Card")
})

test("Subpixel-Rauschen loest keinen Clip aus", () => {
  const rects = [{ left: 0, right: 600.3 }, { left: 600, right: 1200 }]
  assert.deepEqual(overhangClips(rects), [0, 0])
})

test("eine einzelne Card wird nicht geclippt", () => {
  assert.deepEqual(overhangClips([{ left: 0, right: 600 }]), [0])
  assert.deepEqual(overhangClips([]), [])
})
