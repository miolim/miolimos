// #816: Fetch-Glue für den Server-Verlauf — getestet mit gestubbtem fetch.
import { test, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { StackSnapshotSync } from "../../app/javascript/lib/stack_snapshot_sync.js"

let calls
beforeEach(() => { calls = [] })

function stubFetch(responder) {
  globalThis.fetch = async (url, opts = {}) => {
    calls.push({ url, method: opts.method || "GET", body: opts.body })
    return responder(url, opts)
  }
}

const okJson = data => ({ ok: true, json: async () => data })

test("fetchBucket maps server entries to client shape", async () => {
  stubFetch(() => okJson({ entries: [
    { id: 5, trail: [["u1"]], current: 0, pinned: true, savedAt: "2026-07-06T00:00:00Z" }
  ] }))
  const entries = await StackSnapshotSync.fetchBucket("knowledge.stack.history")
  assert.equal(entries.length, 1)
  assert.equal(entries[0].serverId, 5)
  assert.equal(entries[0].pinned, true)
  assert.match(calls[0].url, /key=knowledge\.stack\.history/)
})

test("fetchBucket returns null on http error or network failure", async () => {
  stubFetch(() => ({ ok: false }))
  assert.equal(await StackSnapshotSync.fetchBucket("k"), null)
  stubFetch(() => { throw new Error("offline") })
  assert.equal(await StackSnapshotSync.fetchBucket("k"), null)
})

test("pushSnapshot posts trail and stores serverId on the entry", async () => {
  stubFetch(() => okJson({ id: 42 }))
  const entry = { trail: [["u1"], ["u1", "u2"]], current: 1 }
  const id = await StackSnapshotSync.pushSnapshot("k", entry)
  assert.equal(id, 42)
  assert.equal(entry.serverId, 42)
  const body = JSON.parse(calls[0].body)
  assert.equal(body.key, "k")
  assert.deepEqual(body.trail, [["u1"], ["u1", "u2"]])
})

test("setPinned and remove are no-ops without serverId", async () => {
  stubFetch(() => okJson({}))
  await StackSnapshotSync.setPinned(null, true)
  await StackSnapshotSync.remove(undefined)
  assert.equal(calls.length, 0)
})

test("setPinned patches, remove deletes", async () => {
  stubFetch(() => okJson({}))
  await StackSnapshotSync.setPinned(9, true)
  await StackSnapshotSync.remove(9)
  assert.deepEqual(calls.map(c => c.method), ["PATCH", "DELETE"])
  assert.match(calls[0].url, /\/stack_snapshots\/9/)
})
