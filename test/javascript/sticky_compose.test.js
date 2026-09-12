// #1572: Geometrie des bottom-sticky Antwort-Felds.
// Laeuft ohne Build-Step/DOM: `node --test test/javascript/`.
import { test } from "node:test"
import assert from "node:assert/strict"
import { composeHeight, spacerHeight, scrollTopForCaret } from "../../app/javascript/lib/sticky_compose.js"

const MIN = 62   // zwei Zeilen inkl. Padding/Border

test("Platz komplett sichtbar: Feld bleibt voll ausgefahren", () => {
  // Unterkante des Platzhalters liegt ueber der Kante des Containers.
  assert.equal(composeHeight({
    fullHeight: 300, minHeight: MIN, anchorBottom: 700, viewBottom: 900
  }), 300)
})

test("genau buendig: noch volle Hoehe, kein Schrumpfen um 1px", () => {
  assert.equal(composeHeight({
    fullHeight: 300, minHeight: MIN, anchorBottom: 900, viewBottom: 900
  }), 300)
})

test("100px hochgescrollt: Feld gibt genau 100px ab", () => {
  assert.equal(composeHeight({
    fullHeight: 300, minHeight: MIN, anchorBottom: 1000, viewBottom: 900
  }), 200)
})

test("weiter hochgescrollt: Untergrenze haelt, das Feld klebt in Minimalgroesse", () => {
  assert.equal(composeHeight({
    fullHeight: 300, minHeight: MIN, anchorBottom: 5000, viewBottom: 900
  }), MIN)
})

test("leeres Feld: Untergrenze wird nicht zum Aufblasen benutzt (#1572, Hans)", () => {
  // Ein frisches Feld ist selbst nur zwei Zeilen hoch — es soll kleben,
  // aber nicht groesser werden als sein Inhalt.
  assert.equal(composeHeight({
    fullHeight: 40, minHeight: MIN, anchorBottom: 5000, viewBottom: 900
  }), 40)
})

test("Entwurf laenger als die Card: schrumpft trotzdem nur bis zur Untergrenze", () => {
  assert.equal(composeHeight({
    fullHeight: 2000, minHeight: MIN, anchorBottom: 3000, viewBottom: 900
  }), MIN)
})

test("Platzhalter gleicht genau die abgegebene Hoehe aus", () => {
  assert.equal(spacerHeight({ fullHeight: 300, height: 200 }), 100)
  assert.equal(spacerHeight({ fullHeight: 300, height: 300 }), 0)
  // Defensive: nie negativ, sonst waechst die Card beim Schrumpfen.
  assert.equal(spacerHeight({ fullHeight: 300, height: 340 }), 0)
})

test("Cursor unter dem Ausschnitt: Ausschnitt wandert genau so weit mit", () => {
  assert.equal(scrollTopForCaret({
    caretTop: 480, caretHeight: 20, scrollTop: 0, clientHeight: 60
  }), 440)
})

test("Cursor ueber dem Ausschnitt: Ausschnitt springt an die Cursor-Zeile", () => {
  assert.equal(scrollTopForCaret({
    caretTop: 100, caretHeight: 20, scrollTop: 300, clientHeight: 60
  }), 100)
})

test("Cursor bereits sichtbar: Ausschnitt bleibt unveraendert", () => {
  assert.equal(scrollTopForCaret({
    caretTop: 320, caretHeight: 20, scrollTop: 300, clientHeight: 60
  }), 300)
})
