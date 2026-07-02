// #378 Phase 9 (Hans, 2026-05-26): Trail-/History-/Session-Logic aus
// blade_stack_controller.js ausgelagert. Reine State-Mechanik auf den
// Controller-Properties this.trail + this.currentIndex + this.history;
// Persistenz nach localStorage (via BladeStackHistory) und
// sessionStorage. Wird als Mixin auf das Controller-Prototype
// angewendet, damit `this` weiterhin den Stack-Controller meint
// (Targets, openUuids, appendCardBare, restickify, applyHighlighting,
// syncUrl, _appendBladeAtUrl, _urlForStackId etc.). Reines Code-Move,
// kein Verhalten geaendert.
//
// Enthaltene Methoden:
//   trailBack / trailForward         — Action-Handler (1-Liner)
//   pushTrailState                   — Mutation -> neuer Trail-Eintrag
//   stepTrail                        — currentIndex anpassen + apply
//   applyTrailState                  — DOM auf trail[currentIndex] setzen
//   refreshTrailControls             — Back/Forward-Buttons + Step-Counter
//   restoreLastFromHistoryIfAny      — beim Load aus localStorage
//   snapshotToHistory                — Trail in localStorage persistieren
//   syncFromUrl                      — popstate-Handler
//   _sessionKey                      — sessionStorage-Key fuer pfad
//   _persistSession                  — sessionStorage-Write
//   _restoreSessionStackIfNeeded     — beim Connect ohne ?stack=

export const BladeStackTrailMixin = {
  // ─── Action-Handler ───────────────────────────────────────────────
  trailBack(event)    { event?.preventDefault(); this.stepTrail(-1) },
  trailForward(event) { event?.preventDefault(); this.stepTrail(+1) },

  // ─── Trail-Mechanik ─────────────────────────────────────────────

  // Nach jeder Mutation (Wikilink-Klick, Close, etc.): aktuellen DOM-
  // State als neuen Trail-Eintrag pushen. Wenn currentIndex < length-1,
  // wird der Forward-Teil verworfen (Browser-Verhalten).
  pushTrailState() {
    const state = this.openUuids()
    if (this.currentIndex < this.trail.length - 1) {
      this.trail = this.trail.slice(0, this.currentIndex + 1)
    }
    // Falls neuer State identisch zum letzten ist (z.B. closeCard
    // einer leeren Card): nicht doppelt pushen.
    const last = this.trail[this.trail.length - 1]
    if (!last || state.join(",") !== last.join(",")) {
      this.trail.push(state)
      // Trail-Länge begrenzen — älteste fliegt raus.
      const max = this.constructor.MAX_TRAIL_LENGTH
      if (this.trail.length > max) {
        this.trail = this.trail.slice(this.trail.length - max)
      }
      this.currentIndex = this.trail.length - 1
    }
    this.restickify()
    this.applyHighlighting()
    this.refreshTrailControls()
    this.syncUrl({ pushHistory: false })
  },

  // Trail-Schritt — currentIndex anpassen, DOM auf trail[currentIndex] setzen.
  async stepTrail(delta) {
    const target = this.currentIndex + delta
    if (target < 0 || target >= this.trail.length) return
    this.currentIndex = target
    await this.applyTrailState({ pushHistory: false })
    this.refreshTrailControls()
  },

  // Setzt das DOM gemäß trail[currentIndex] — entweder durch Card-
  // Append/Remove oder durch innerHTML-Reset bei größeren Sprüngen.
  async applyTrailState({ pushHistory }) {
    const target = this.trail[this.currentIndex] || []
    const current = this.openUuids()

    // Wenn target ein Prefix von current ist: nur abschneiden.
    if (current.length > target.length &&
        current.slice(0, target.length).join(",") === target.join(",")) {
      const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
      // #593: Entwurfs-Schutz — abgeschnittene Cards können dirty Forms tragen.
      if (!this._confirmDiscardDrafts(cards.slice(target.length))) return
      cards.slice(target.length).forEach(c => c.remove())
    }
    // Wenn current ein Prefix von target ist: anhängen.
    else if (target.length > current.length &&
             target.slice(0, current.length).join(",") === current.join(",")) {
      for (let i = current.length; i < target.length; i++) {
        await this.appendCardBare(target[i])
      }
    }
    // Sonst: kompletter Reset (selten — z.B. bei restoreFromHistory).
    else {
      // #593: Reset verwirft ALLE Cards — Entwürfe schützen.
      if (!this._confirmDiscardDrafts(Array.from(this.containerTarget.querySelectorAll(".stack-card")))) return
      this.containerTarget.innerHTML = ""
      for (const uuid of target) await this.appendCardBare(uuid)
    }

    this.restickify()
    this.applyHighlighting()
    this.syncUrl({ pushHistory })
  },

  refreshTrailControls() {
    const canBack = this.currentIndex > 0
    const canFwd  = this.currentIndex < this.trail.length - 1
    if (this.hasTrailBackTarget)    this.trailBackTarget.disabled    = !canBack
    if (this.hasTrailForwardTarget) this.trailForwardTarget.disabled = !canFwd
    if (this.hasTrailStepTarget) {
      if (this.trail.length <= 1) {
        this.trailStepTarget.classList.add("hidden")
      } else {
        this.trailStepTarget.classList.remove("hidden")
        this.trailStepTarget.textContent = `${this.currentIndex + 1} / ${this.trail.length}`
      }
    }
  },

  // ─── localStorage-History ───────────────────────────────────────

  // Beim Page-Load ohne ?stack=…-Param: prüft localStorage und stellt
  // den letzten (jüngsten) Eintrag wieder her — der User landet
  // dort, wo er aufgehört hat.
  async restoreLastFromHistoryIfAny() {
    const latest = this.history.latest()
    if (!latest) return
    this.trail        = latest.trail.map(s => Array.from(s))
    this.currentIndex = latest.current
    await this.applyTrailState({ pushHistory: false })
    this.refreshTrailControls()
  },

  // Snapshot des aktuellen Trails. Persistenz-Logik (dedupe, pinned,
  // trim) lebt im BladeStackHistory-Helper — dieser Controller weiss
  // nur, dass es einen Snapshot-Aufruf gibt.
  snapshotToHistory() {
    this.history?.snapshot({ trail: this.trail, current: this.currentIndex })
  },

  // popstate (Browser-Back/Forward zwischen großen Stack-Wechseln):
  // Trail wird komplett zurückgesetzt auf URL-State.
  async syncFromUrl() {
    const url = new URL(window.location.href)
    const raw = url.searchParams.get("stack") || ""
    const uuids = raw.split(",").map(s => s.trim()).filter(Boolean)
    this.snapshotToHistory()
    this.containerTarget.innerHTML = ""
    for (const uuid of uuids) await this.appendCardBare(uuid)
    this.trail        = uuids.length ? [uuids] : []
    this.currentIndex = uuids.length ? 0 : -1
    // #434 (Hans, 2026-06-01): erstes Blade kann sich beim popstate aendern
    // -> History-Bucket nachziehen (siehe _rekeyHistory im Controller).
    this._rekeyHistory?.()
    this.restickify()
    this.applyHighlighting()
    this.refreshTrailControls()
  },

  // ─── sessionStorage-Persistenz ───────────────────────────────────

  _sessionKey() { return `stack.${window.location.pathname}` },
  // #434 (Hans, 2026-06-01): Parallel-Key in localStorage, damit der letzte
  // Stack einen Browser-Neustart uebersteht (sessionStorage wird beim
  // Schliessen geleert -> bisher war der Stack "am naechsten Tag" weg).
  _lastStackKey() { return `stack.last.${window.location.pathname}` },

  _persistSession(uuids) {
    const val = uuids.join(",")
    try {
      if (uuids.length) sessionStorage.setItem(this._sessionKey(), val)
      else              sessionStorage.removeItem(this._sessionKey())
    } catch (_) { /* sessionStorage might be unavailable — silent */ }
    // #434: zusaetzlich persistent (localStorage) fuer den Neustart-Restore.
    try {
      if (uuids.length) localStorage.setItem(this._lastStackKey(), val)
      else              localStorage.removeItem(this._lastStackKey())
    } catch (_) { /* silent */ }
  },

  // #265: beim Connect ohne ?stack=-Param den gespeicherten Stand
  // restaurieren — fehlende Cards einfach via _appendBladeAtUrl
  // hinten anhaengen. Wenn die Server-Page schon eine Default-Card
  // gerendert hat (z.B. list:dashboard), bleibt die stehen; die
  // anderen Cards aus der Session kommen einfach dahinter.
  async _restoreSessionStackIfNeeded() {
    const url = new URL(window.location.href)
    if (url.searchParams.get("stack")) return  // explizite URL gewinnt
    let saved
    try { saved = sessionStorage.getItem(this._sessionKey()) } catch (_) { /* silent */ }
    // #434 (Hans, 2026-06-01): nach einem Browser-Neustart ist sessionStorage
    // leer — dann den letzten Stack aus localStorage wiederherstellen.
    if (!saved) { try { saved = localStorage.getItem(this._lastStackKey()) } catch (_) { /* silent */ } }
    if (!saved) return
    const ids = saved.split(",").map(s => s.trim()).filter(Boolean)
    if (!ids.length) return
    const open = new Set(this.openUuids())
    for (const id of ids) {
      if (open.has(id)) continue
      const cardUrl = this._urlForStackId(id)
      if (!cardUrl) continue
      try { await this._appendBladeAtUrl({ stackId: id, url: cardUrl, forceNew: false }) }
      catch (e) { console.warn("session-restore: failed for", id, e) }
    }
  }
}
