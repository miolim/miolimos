import { Controller } from "@hotwired/stimulus"

// #1644 (Hans): „Ich hätte gern oben zwei Optionsfelder: Person |
// Organisation … Dann abhängig von der Option: Vorname/Nachname, Geschlecht
// oder Organisationsname, Rechtsform."
//
// Schaltet im Quick-Create-Slot zwischen den beiden Entitäts-Arten um: setzt
// das versteckte `item_type`, zeigt die passende Feldgruppe und DEAKTIVIERT
// die Felder der anderen — deaktivierte Felder schickt der Browser nicht mit,
// sonst landeten leere Namensfelder in einer Organisation (und umgekehrt).
//
// Markup:
//   <div data-controller="entity-type-switch" data-entity-type-switch-typ-value="person">
//     <button data-action="entity-type-switch#waehlen" data-entity-type-switch-typ-param="person"
//             data-entity-type-switch-target="knopf" data-typ="person">…</button>
//     <input type="hidden" name="item_type" data-entity-type-switch-target="feldTyp">
//     <div data-entity-type-switch-target="gruppe" data-typ="person">…</div>
//   </div>
export default class extends Controller {
  static targets = ["knopf", "gruppe", "feldTyp"]
  static values  = { typ: { type: String, default: "person" } }

  connect() {
    this.anwenden()
  }

  waehlen(event) {
    event.preventDefault()
    this.typValue = event.params.typ
    this.anwenden()
    // Nach dem Umschalten ins erste Feld der sichtbaren Gruppe.
    const gruppe = this.gruppeTargets.find((g) => g.dataset.typ === this.typValue)
    gruppe?.querySelector("input:not([type=hidden]), select")?.focus()
  }

  anwenden() {
    const typ = this.typValue
    if (this.hasFeldTypTarget) this.feldTypTarget.value = typ

    this.knopfTargets.forEach((k) => {
      const aktiv = k.dataset.typ === typ
      k.setAttribute("aria-pressed", String(aktiv))
      k.dataset.aktiv = String(aktiv)
    })

    this.gruppeTargets.forEach((g) => {
      const aktiv = g.dataset.typ === typ
      g.classList.toggle("hidden", !aktiv)
      g.querySelectorAll("input, select, textarea").forEach((f) => { f.disabled = !aktiv })
    })
  }
}
