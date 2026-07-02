import { Controller } from "@hotwired/stimulus"

// #652 (Hans, 2026-06-12): Der Beschreibungs-Section-Header haftete mit
// festem top-9 — geeicht auf EINZEILIGE KI-Titel. Bei umbrochenen
// (zweizeiligen) Titeln verdeckte die zweite Titelzeile den Header
// samt Suchfeld. Dieser Controller misst den (sticky, -top-4) Titel-
// balken und meldet die passende Haft-Kante als CSS-Var an den
// Container; die Section-Header nutzen `top: var(--ki-title-h, 2.25rem)`.
export default class extends Controller {
  static targets = ["bar"]

  connect() {
    this._ro = new ResizeObserver(() => this._apply())
    if (this.hasBarTarget) this._ro.observe(this.barTarget)
    this._apply()
  }

  disconnect() {
    this._ro?.disconnect()
  }

  _apply() {
    if (!this.hasBarTarget) return
    // Titelbalken haftet bei -top-4 (1rem Überhang) — sichtbare
    // Unterkante = Höhe minus 1rem (16px).
    const h = this.barTarget.offsetHeight
    if (h > 0) this.element.style.setProperty("--ki-title-h", `${Math.max(h - 16, 0)}px`)
  }
}
