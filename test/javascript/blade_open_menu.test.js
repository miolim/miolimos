// #1642: Ein Modifier statt drei Kombinationen. Geprüft wird die Entscheidung
// ohne DOM: `node --test test/javascript/`.
import { test } from "node:test"
import assert from "node:assert/strict"
import { grundart, OEFFNUNGSARTEN } from "../../app/javascript/lib/blade_open_menu.js"

test("schlichter Klick ersetzt", () => {
  assert.equal(grundart({}), "ersetzen")
  assert.equal(grundart(undefined), "ersetzen")
})

test("Umschalt fragt per Menue", () => {
  assert.equal(grundart({ shiftKey: true }), "menue")
})

test("Alt ist kein Modifier mehr (#1509 abgeloest)", () => {
  assert.equal(grundart({ altKey: true }), "ersetzen")
  assert.equal(grundart({ altKey: true, shiftKey: true }), "menue",
               "Umschalt sticht — Alt spielt keine Rolle mehr")
})

test("Cmd/Strg gehoert dem Browser", () => {
  assert.equal(grundart({ metaKey: true }), "browser")
  assert.equal(grundart({ ctrlKey: true }), "browser")
  assert.equal(grundart({ ctrlKey: true, shiftKey: true }), "browser",
               "auch mit Umschalt: erst der Browser")
})

test("das Menue bietet genau die vier Oeffnungsarten", () => {
  assert.deepEqual(OEFFNUNGSARTEN, ["ende", "rechts", "links", "ersetzen"])
})
