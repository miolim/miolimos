// #801 P3: Unit-Tests für die Stack-History-Persistenz (#206 Phase 2) —
// dedupe, pinned-Schutz, HISTORY_MAX-Trim, Backward-Compat (uuids-Format).
// localStorage wird mit einem Mini-Shim ersetzt (Node hat keins).
import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"

const store = new Map()
globalThis.localStorage = {
  getItem: k => (store.has(k) ? store.get(k) : null),
  setItem: (k, v) => store.set(k, String(v)),
  removeItem: k => store.delete(k),
}

const { BladeStackHistory, NOTE_STACK_HISTORY_MAX } =
  await import("../../app/javascript/lib/blade_stack_history.js")

beforeEach(() => store.clear())

const history = () => new BladeStackHistory("test-key")

test("load returns [] for missing or corrupt storage", () => {
  assert.deepEqual(history().load(), [])
  store.set("test-key", "{kaputt")
  assert.deepEqual(history().load(), [])
})

test("snapshot + latest round-trip trail and current index", () => {
  const h = history()
  h.snapshot({ trail: [["u1"], ["u1", "u2"]], current: 1 })
  assert.deepEqual(h.latest(), { trail: [["u1"], ["u1", "u2"]], current: 1 })
})

test("snapshot ignores empty trails", () => {
  const h = history()
  h.snapshot({ trail: [], current: 0 })
  h.snapshot({ trail: [[]], current: 0 })
  assert.equal(h.load().length, 0)
})

test("snapshot dedupes by final composition, newest wins", () => {
  const h = history()
  h.snapshot({ trail: [["u1", "u2"]], current: 0 })
  h.snapshot({ trail: [["andere"]], current: 0 })
  h.snapshot({ trail: [["u1"], ["u1", "u2"]], current: 1 })  // gleiche Final-Komposition wie #1
  const entries = h.load()
  assert.equal(entries.length, 2)
  assert.equal(entries.filter(e => e.trail.at(-1).join(",") === "u1,u2").length, 1)
})

test("pinned entries are updated in place, not duplicated", () => {
  const h = history()
  h.snapshot({ trail: [["u1"]], current: 0 })
  const entries = h.load()
  entries[0].pinned = true
  store.set("test-key", JSON.stringify(entries))

  h.snapshot({ trail: [["start"], ["u1"]], current: 1 })
  const after = h.load()
  assert.equal(after.length, 1)
  assert.equal(after[0].pinned, true)
  assert.deepEqual(after[0].trail, [["start"], ["u1"]])
})

test("trim caps non-pinned entries at HISTORY_MAX but keeps pinned", () => {
  const h = history()
  // ein gepinnter Alt-Eintrag …
  h.snapshot({ trail: [["pin-mich"]], current: 0 })
  const seed = h.load()
  seed[0].pinned = true
  store.set("test-key", JSON.stringify(seed))
  // … plus MAX+3 frische Einträge
  for (let i = 0; i < NOTE_STACK_HISTORY_MAX + 3; i++) {
    h.snapshot({ trail: [[`u${i}`]], current: 0 })
  }
  const entries = h.load()
  assert.equal(entries.filter(e => !e.pinned).length, NOTE_STACK_HISTORY_MAX)
  assert.equal(entries.filter(e => e.pinned).length, 1)
})

test("latest converts the legacy uuids format to a one-line trail", () => {
  store.set("test-key", JSON.stringify([{ uuids: "u1,u2", pinned: false }]))
  assert.deepEqual(history().latest(), { trail: [["u1", "u2"]], current: 0 })
})

test("latest returns null when nothing usable is stored", () => {
  assert.equal(history().latest(), null)
  store.set("test-key", JSON.stringify([{ uuids: "", pinned: false }]))
  assert.equal(history().latest(), null)
})

// #816: snapshot gibt den geschriebenen Eintrag zurück (Server-Spiegelung)
test("snapshot returns the written entry and null for empty trails", () => {
  const h = history()
  const entry = h.snapshot({ trail: [["u1"]], current: 0 })
  assert.deepEqual(entry.trail, [["u1"]])
  assert.equal(entry.pinned, false)
  assert.ok(entry.savedAt)
  assert.equal(h.snapshot({ trail: [], current: 0 }), null)
})

// #816: replaceAll ersetzt den Bucket (Server ist die Wahrheit)
test("replaceAll overwrites the bucket wholesale", () => {
  const h = history()
  h.snapshot({ trail: [["alt"]], current: 0 })
  h.replaceAll([{ trail: [["neu"]], current: 0, pinned: true, serverId: 7 }])
  const entries = h.load()
  assert.equal(entries.length, 1)
  assert.equal(entries[0].serverId, 7)
  h.replaceAll(null)
  assert.deepEqual(h.load(), [])
})

test("latest clamps a stale current index into the trail range", () => {
  store.set("test-key", JSON.stringify([{ trail: [["u1"], ["u1", "u2"]], current: 99 }]))
  assert.equal(history().latest().current, 1)
})
