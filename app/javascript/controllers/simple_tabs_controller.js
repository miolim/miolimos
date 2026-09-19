import { Controller } from "@hotwired/stimulus"

// #533 #5 (Hans, 2026-06-07): schlichte clientseitige Reiter. Tabs + Panels
// tragen data-name; Klick auf einen Tab zeigt das passende Panel und hebt den
// Tab hervor. Keine Server-Last (alle Reiter sind schon gerendert).
export default class extends Controller {
  static targets = ["tab", "panel"]
  // #915 (Hans): optionaler storage-key — merkt den aktiven Reiter (sessionStorage)
  // und stellt ihn nach Re-Render/Reload wieder her, statt auf den ersten Reiter
  // zu springen. Ohne Key: bisheriges Verhalten (erster Reiter).
  //
  // #1674 (aus immoOS #1567 uebernommen): `initial` sagt, mit welchem Reiter die
  // Card AUFGEHT, wenn sie zu einem bestimmten Zweck geoeffnet wurde. Er
  // schlaegt das Gedaechtnis: Wer ueber einen gezielten Verweis kommt, will
  // diesen Reiter sehen und nicht den, den er beim letzten Mal offen hatte.
  //
  // Und er wird gleich gemerkt: Sonst spraenge die Card beim naechsten
  // Re-Render wieder auf den alten Reiter zurueck — die Query ist dann
  // laengst weg.
  static values = { storageKey: String, initial: String }

  connect() {
    const names  = this.tabTargets.map((t) => t.dataset.name)
    const wunsch = this.hasInitialValue && names.includes(this.initialValue) ? this.initialValue : null
    const stored = this.hasStorageKeyValue ? sessionStorage.getItem(this._key()) : null
    const target = wunsch || (stored && names.includes(stored) ? stored : names[0])
    if (target) this._activate(target)
    if (wunsch && this.hasStorageKeyValue) sessionStorage.setItem(this._key(), wunsch)
  }

  show(event) {
    const name = event.currentTarget?.dataset.name
    if (!name) return
    this._activate(name)
    if (this.hasStorageKeyValue) sessionStorage.setItem(this._key(), name)
  }

  // #1566 R3 (immoOS): von außen einen Reiter zeigen — für einen Anker, der in
  // einem verborgenen Reiter liegt (blade_stack_scroll#scrollToAnchorInCard).
  // Gemerkt wie beim Klick, sonst spränge die Card beim nächsten Re-Render
  // zurück.
  zeige(name) {
    if (!this.tabTargets.some((t) => t.dataset.name === name)) return
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
    // #1674 (aus immoOS #1665 uebernommen): Der Reiterwechsel sagt an, was
    // jetzt offen ist — `simple-tabs:gewechselt`, mit dem Reiternamen im
    // Detail. Wer darauf hoert, entscheidet selbst (dort: die Hilfe-Card folgt
    // dem Reiter). Bewusst auch beim connect: So erfaehrt ein Zuhoerer auch den
    // Reiter, den die Card sich gemerkt hat.
    this.dispatch("gewechselt", { detail: { name } })
  }
}
