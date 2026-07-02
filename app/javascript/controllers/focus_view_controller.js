import { Controller } from "@hotwired/stimulus"

// #685 (Hans, 2026-06-13): Persistente Fokusansichten (nur Desktop, CSS
// gated >= md). Der Controller sitzt am <body> und überlebt damit
// Card-/Frame-Re-Renders (Bearbeiten/Speichern) — der Fokus bleibt
// unabhängig von Edit-/View-Wechseln erhalten.
//   data-focus-trigger="blade"   — Single Blade: nur das aktuelle Detail-
//     Blade, zentriert, eigene persistierte Breite per Drag-Handle.
//   data-focus-trigger="section" — Single Section: nur die Beschreibungs-
//     Section (Pfad Section→Card freigestellt, Off-Path-Geschwister weg).
// Verlassen per ESC oder erneutem Klick. Icon-Wechsel (enter↔exit) läuft
// rein über CSS (body-Klasse + data-Attribute), bleibt also nach
// Re-Renders automatisch korrekt.
export default class extends Controller {
  connect() {
    this.mode     = null   // "blade" | "section" | null
    this.cardUuid = null
    this._onClick = (e) => this._handleClick(e)
    this._onKey   = (e) => { if (e.key === "Escape" && this.mode) { e.preventDefault(); this.exit() } }
    // Re-Apply nach jedem DOM-Umbau (Edit-Frame ODER Save-Turbo-Stream) —
    // ein MutationObserver fängt beides; rAF-debounced, läuft nur solange
    // der Fokus aktiv ist. So bleibt der Fokus über Bearbeiten/Speichern.
    this._observer = new MutationObserver(() => {
      if (!this.mode) return
      // Nur re-applien, wenn der Fokus-Marker durch einen Re-Render verloren
      // ging — NICHT bei jeder Editor-Tastatureingabe (cm6 mutiert beim
      // Tippen das DOM, lässt aber section/card-Marker unberührt).
      const stillApplied = this.mode === "blade"
        ? document.querySelector(".stack-card[data-focus-blade]")
        : document.querySelector("[data-focus-section-active]")
      if (stillApplied) return
      cancelAnimationFrame(this._raf)
      this._raf = requestAnimationFrame(() => this._apply())
    })
    this.element.addEventListener("click", this._onClick)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    this.element.removeEventListener("click", this._onClick)
    document.removeEventListener("keydown", this._onKey)
    this._observer?.disconnect()
    cancelAnimationFrame(this._raf)
  }

  _handleClick(e) {
    const trig = e.target.closest?.("[data-focus-trigger]")
    if (!trig) return
    e.preventDefault()
    const mode = trig.dataset.focusTrigger
    const card = trig.closest(".stack-card")
    if (!card) return
    if (this.mode === mode && this.cardUuid === card.dataset.uuid) { this.exit(); return }
    this.mode     = mode
    this.cardUuid = card.dataset.uuid
    this._apply()
  }

  exit() {
    this.mode = null
    this.cardUuid = null
    this._observer.disconnect()
    cancelAnimationFrame(this._raf)
    this._clearMarkers()
    document.body.classList.remove("focus-blade", "focus-section")
  }

  // Fokus (neu) anwenden — idempotent, wird auch nach jedem Re-Render des
  // Detail-Frames erneut gerufen, damit der Fokus erhalten bleibt.
  _apply() {
    if (!this.mode) return
    const card = this.cardUuid
      ? document.querySelector(`.stack-card[data-uuid="${CSS.escape(this.cardUuid)}"]`)
      : null
    if (!card) { this.exit(); return }   // fokussierte Card ist weg → beenden
    // Observer während der eigenen DOM-Mutationen pausieren (sonst feuert er
    // auf die selbst gesetzten Klassen/Attribute → Endlosschleife).
    this._observer.disconnect()
    this._clearMarkers()
    card.dataset.focusBlade = "true"
    document.body.classList.toggle("focus-blade",   this.mode === "blade")
    document.body.classList.toggle("focus-section", this.mode === "section")

    if (this.mode === "blade") {
      const saved = localStorage.getItem("focus.blade.width")
      if (saved) card.style.setProperty("--focus-blade-width", saved)
      this._addWidthHandle(card)
    } else if (this.mode === "section") {
      const section = card.querySelector("[data-focus-section]")
      if (!section) { this.exit(); return }
      section.dataset.focusSectionActive = "true"
      // Pfad Section→Card freistellen: auf jeder Ebene Off-Path-Geschwister
      // ausblenden (robust gegen Verschachtelung; blendet den Spine mit aus).
      let el = section
      while (el && el !== card && el.parentElement) {
        for (const sib of el.parentElement.children) {
          if (sib !== el) sib.classList.add("focus-section-off")
        }
        el = el.parentElement
      }
    }
    // Beobachtung wieder aufnehmen — fängt den nächsten Re-Render.
    this._observer.observe(document.body, { childList: true, subtree: true })
  }

  _clearMarkers() {
    document.querySelectorAll(".focus-section-off").forEach(el => el.classList.remove("focus-section-off"))
    document.querySelectorAll("[data-focus-section-active]").forEach(s => delete s.dataset.focusSectionActive)
    document.querySelectorAll(".stack-card[data-focus-blade]").forEach(c => {
      delete c.dataset.focusBlade
      c.querySelector(":scope > .focus-blade-width-handle")?.remove()
    })
  }

  _addWidthHandle(card) {
    if (card.querySelector(":scope > .focus-blade-width-handle")) return
    const handle = document.createElement("div")
    handle.className = "focus-blade-width-handle"
    handle.title = "Breite ziehen (nur Fokusansicht)"
    const onMove = (e) => {
      const rect = card.getBoundingClientRect()
      const w = Math.max(320, Math.min(e.clientX - rect.left, window.innerWidth * 0.95))
      card.style.setProperty("--focus-blade-width", `${Math.round(w)}px`)
    }
    const onUp = () => {
      document.removeEventListener("pointermove", onMove)
      document.removeEventListener("pointerup", onUp)
      const w = card.style.getPropertyValue("--focus-blade-width")
      if (w) localStorage.setItem("focus.blade.width", w)
    }
    handle.addEventListener("pointerdown", (e) => {
      e.preventDefault()
      document.addEventListener("pointermove", onMove)
      document.addEventListener("pointerup", onUp)
    })
    card.appendChild(handle)
  }
}
