import { Controller } from "@hotwired/stimulus"

// #462 (Hans, 2026-06-02): Client-seitiger Entitaets-Filter fuer das
// Verlauf-Blade im Stack (die Vollansicht filtert server-seitig; das
// Blade zeigt nur die geladenen Top-Eintraege, daher reicht hier ein
// Sichtbarkeits-Toggle). Pills togglen die <li> nach data-type —
// additiv, leere Auswahl = alle.
export default class extends Controller {
  static targets = ["item", "pill"]

  connect() { this.active ||= new Set(); this.apply() }

  // #631 v2: „Mehr laden" haengt neue Zeilen an — aktiven Filter
  // direkt auf den frischen Target anwenden.
  itemTargetConnected(li) {
    const any = this.active?.size > 0
    li.classList.toggle("hidden", any && !this.active.has(li.dataset.type))
  }

  toggle(event) {
    const type = event.currentTarget.dataset.type || ""
    if (type === "") this.active.clear()
    else if (this.active.has(type)) this.active.delete(type)
    else this.active.add(type)
    this.apply()
  }

  apply() {
    const any = this.active.size > 0
    this.itemTargets.forEach(li => {
      li.classList.toggle("hidden", any && !this.active.has(li.dataset.type))
    })
    this.pillTargets.forEach(p => {
      const t  = p.dataset.type || ""
      const on = (t === "" && !any) || (t !== "" && this.active.has(t))
      p.classList.toggle("bg-slate-700", on)
      p.classList.toggle("text-white", on)
      p.classList.toggle("text-slate-600", !on)
    })
  }
}
