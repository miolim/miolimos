import { Controller } from "@hotwired/stimulus"

// #533 #5 (Hans, 2026-06-07): schlichte clientseitige Reiter. Tabs + Panels
// tragen data-name; Klick auf einen Tab zeigt das passende Panel und hebt den
// Tab hervor. Keine Server-Last (alle Reiter sind schon gerendert).
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    const first = this.tabTargets[0]?.dataset.name
    if (first) this._activate(first)
  }

  show(event) {
    const name = event.currentTarget?.dataset.name
    if (name) this._activate(name)
  }

  _activate(name) {
    this.panelTargets.forEach((p) => p.classList.toggle("hidden", p.dataset.name !== name))
    this.tabTargets.forEach((t) => {
      const active = t.dataset.name === name
      t.classList.toggle("border-emerald-500", active)
      t.classList.toggle("text-emerald-700", active)
      t.classList.toggle("font-medium", active)
      t.classList.toggle("border-transparent", !active)
      t.classList.toggle("text-slate-500", !active)
    })
  }
}
