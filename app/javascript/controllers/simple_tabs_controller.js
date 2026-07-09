import { Controller } from "@hotwired/stimulus"

// #533 #5 (Hans, 2026-06-07): schlichte clientseitige Reiter. Tabs + Panels
// tragen data-name; Klick auf einen Tab zeigt das passende Panel und hebt den
// Tab hervor. Keine Server-Last (alle Reiter sind schon gerendert).
export default class extends Controller {
  static targets = ["tab", "panel"]
  // #915 (Hans): optionaler storage-key — merkt den aktiven Reiter (sessionStorage)
  // und stellt ihn nach Re-Render/Reload wieder her, statt auf den ersten Reiter
  // zu springen. Ohne Key: bisheriges Verhalten (erster Reiter).
  static values = { storageKey: String }

  connect() {
    const names  = this.tabTargets.map((t) => t.dataset.name)
    const stored = this.hasStorageKeyValue ? sessionStorage.getItem(this._key()) : null
    const target = stored && names.includes(stored) ? stored : names[0]
    if (target) this._activate(target)
  }

  show(event) {
    const name = event.currentTarget?.dataset.name
    if (!name) return
    this._activate(name)
    if (this.hasStorageKeyValue) sessionStorage.setItem(this._key(), name)
  }

  _key() {
    return `simple-tabs:${this.storageKeyValue}`
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
