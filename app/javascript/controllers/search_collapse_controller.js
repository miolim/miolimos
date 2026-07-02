import { Controller } from "@hotwired/stimulus"

// #301: Mobile-Collapse fuer das Suchfeld. Auf Desktop ist das Feld
// immer sichtbar (CSS md:block); auf Mobile wird es zum Lupe-Icon, das
// bei Klick das Feld als fixed Full-Width-Leiste unter der Topbar
// aufklappt — so haben die Quick-Create-Icons auf schmalen Screens
// Platz. Klick ausserhalb / Esc schliesst wieder.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this._outside = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
    document.addEventListener("click", this._outside)
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    document.removeEventListener("click", this._outside)
    document.removeEventListener("keydown", this._onKey)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    const open = !this.panelTarget.classList.contains("hidden")
    if (open) {
      this.close()
    } else {
      this.panelTarget.classList.remove("hidden")
      requestAnimationFrame(() => this.panelTarget.querySelector("input")?.focus())
    }
  }

  // Auf Mobile schliessen (Desktop bleibt durch md:block ohnehin offen).
  close() {
    this.panelTarget.classList.add("hidden")
  }
}
