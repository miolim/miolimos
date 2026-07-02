// #206 Phase 2: Persistenz-Schicht fuer den Note-Stack. Vorher inline
// im blade_stack_controller.js — jetzt eigenstaendiges Modul, damit
// `stack_history_controller.js` (das die Saved-Stacks-Liste rendert)
// dasselbe Read/Write-API benutzen kann und beide Controller dieselbe
// Definition von "pinned"/"trimmed"/"dedupe" teilen.
//
// Datenformat (eine Liste von Entries in localStorage):
//
//   [
//     { trail: [[uuid1], [uuid1, uuid2]], current: 1, pinned: false, savedAt: "ISO" },
//     ...
//   ]
//
// Backward-Compat: alte Eintraege ohne `trail`, aber mit `uuids: "u1,u2"`,
// werden beim Restore in einen einzeiligen Trail konvertiert.

const HISTORY_MAX = 10

export class BladeStackHistory {
  constructor(storageKey) {
    this.storageKey = storageKey
  }

  // Liest die ganze History-Liste. Gibt [] zurueck, wenn nichts oder
  // kaputt — wir wollen keinen JSON-Parse-Fehler bis in den Controller.
  load() {
    try { return JSON.parse(localStorage.getItem(this.storageKey) || "[]") }
    catch (_) { return [] }
  }

  // Liest den juengsten (= 0. Eintrag) raus und gibt { trail, current }
  // zurueck, oder null, wenn keine History da ist. Auch hier
  // Backward-Compat fuer das alte uuids-Format.
  latest() {
    const last = this.load()[0]
    if (!last) return null
    const trail = last.trail || [(last.uuids || "").split(",").filter(Boolean)]
    if (!trail.length || !trail[0].length) return null
    const current = last.current ?? trail.length - 1
    return { trail, current: Math.max(0, Math.min(current, trail.length - 1)) }
  }

  // Snapshot des aktuellen Trails. Dedupliziert per Final-Komposition;
  // pinned-Eintraege werden NIE durch das HISTORY_MAX-Limit verdraengt
  // und auch nicht durch dedupe-Logik geloescht (sondern aktualisiert).
  snapshot({ trail, current }) {
    if (!trail || trail.length === 0) return
    const finalState = trail[trail.length - 1]
    if (!finalState || finalState.length === 0) return

    let history = this.load()
    const dedupKey = finalState.join(",")

    const existingPinned = history.find(h => h.pinned && this._finalOf(h) === dedupKey)
    if (existingPinned) {
      existingPinned.trail   = trail.map(s => Array.from(s))
      existingPinned.current = current
      existingPinned.savedAt = new Date().toISOString()
    } else {
      history = history.filter(h => h.pinned || this._finalOf(h) !== dedupKey)
      history.unshift({
        trail:   trail.map(s => Array.from(s)),
        current: current,
        pinned:  false,
        savedAt: new Date().toISOString()
      })
    }

    history = this._trim(history)
    localStorage.setItem(this.storageKey, JSON.stringify(history))
  }

  // Final-Komposition als String — Dedup-Key zwischen Eintraegen.
  _finalOf(entry) {
    if (!entry.trail) return entry.uuids || ""  // backward-compat
    const last = entry.trail[entry.trail.length - 1] || []
    return last.join(",")
  }

  // Pinned bleiben, non-pinned werden auf HISTORY_MAX gekappt. Sortiert
  // nach savedAt absteigend — frischeste zuerst, pinned und recent
  // zusammen.
  _trim(history) {
    const pinned = history.filter(h => h.pinned)
    const recent = history.filter(h => !h.pinned).slice(0, HISTORY_MAX)
    return [...pinned, ...recent].sort((a, b) =>
      (new Date(b.savedAt)) - (new Date(a.savedAt))
    )
  }
}

export const NOTE_STACK_HISTORY_MAX = HISTORY_MAX
