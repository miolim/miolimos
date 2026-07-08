// #816: Fetch-Glue für den geräteübergreifenden Stack-Verlauf.
// Server (/stack_snapshots) ist die Wahrheit, localStorage der Cache —
// diese Funktionen spiegeln Drawer-Aktionen zum Server. Alle Aufrufer
// behandeln Fehler tolerant (offline → lokales Verhalten bleibt).
//
// Client-Entry-Shape (kompatibel zu BladeStackHistory):
//   { trail, current, pinned, savedAt, serverId }

const HEADERS = { "Accept": "application/json", "Content-Type": "application/json" }

export const StackSnapshotSync = {
  // Server-Liste eines Buckets → Client-Entries (oder null bei Fehler).
  async fetchBucket(key) {
    try {
      const res = await fetch(`/stack_snapshots?key=${encodeURIComponent(key)}`,
        { headers: { "Accept": "application/json" }, credentials: "same-origin" })
      if (!res.ok) return null
      const json = await res.json()
      return (json.entries || []).map(e => ({
        trail: e.trail, current: e.current, pinned: e.pinned,
        savedAt: e.savedAt, serverId: e.id
      }))
    } catch (_) { return null }
  },

  // Write-Through eines Snapshots (fire-and-forget-tauglich).
  // #901: entry.pinned wird mitgesendet, wenn gesetzt — so kann der
  // Drawer den aktuellen Stack direkt als gepinnten Snapshot anlegen
  // (Server dedupt ueber die End-Komposition und promotet vorhandene
  // Recent-Eintraege zu pinned).
  async pushSnapshot(key, entry) {
    try {
      const body = { key, trail: entry.trail, current: entry.current }
      if (entry.pinned != null) body.pinned = entry.pinned
      const res = await fetch("/stack_snapshots", {
        method: "POST", headers: HEADERS, credentials: "same-origin",
        body: JSON.stringify(body)
      })
      if (!res.ok) return null
      const json = await res.json()
      entry.serverId = json.id
      return json.id
    } catch (_) { return null }
  },

  async setPinned(serverId, pinned) {
    if (!serverId) return
    try {
      await fetch(`/stack_snapshots/${serverId}`, {
        method: "PATCH", headers: HEADERS, credentials: "same-origin",
        body: JSON.stringify({ pinned })
      })
    } catch (_) { /* offline-tolerant */ }
  },

  async remove(serverId) {
    if (!serverId) return
    try {
      await fetch(`/stack_snapshots/${serverId}`, { method: "DELETE", credentials: "same-origin" })
    } catch (_) { /* offline-tolerant */ }
  }
}
