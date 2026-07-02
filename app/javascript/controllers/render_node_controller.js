import { Controller } from "@hotwired/stimulus"

// #352 (Hans, 2026-05-25): Toggle fuer Render-Blade-Knoten. Im
// Unterschied zum allgemeinen `disclosure`-Controller brauchen wir
// hier DREI Sichtbarkeitsregeln pro Knoten, die alle vom selben
// open|collapsed-State abhaengen:
//
//   1. icon (Chevron): rotate-90 wenn open
//   2. body          : sichtbar wenn open
//   3. titlePlaceholder: sichtbar wenn collapsed (nur Content-Knoten)
//
// Wir fuehren das ueber ein data-state-Attribut auf dem Root-Element;
// CSS-Regeln (oben im Markup als utility-class-Toggle umgesetzt)
// koennten alternativ greifen, aber explizite Klassen-Toggles sind
// vorhersehbarer.
export default class extends Controller {
  static targets = ["icon", "body", "titlePlaceholder"]
  static values  = { open: { type: Boolean, default: false } }

  connect() { this.apply() }

  // Stimulus value-changed callback — feuert wenn das data-attribute von
  // aussen (z.B. render-blade-toggles bulk-toggle) modifiziert wird.
  openValueChanged() { this.apply() }

  toggle(event) {
    if (event) event.preventDefault()
    this.openValue = !this.openValue
    this.apply()
  }

  apply() {
    const open = this.openValue
    if (this.hasIconTarget) this.iconTarget.classList.toggle("rotate-90", open)
    if (this.hasBodyTarget) this.bodyTarget.classList.toggle("hidden", !open)
    if (this.hasTitlePlaceholderTarget) {
      this.titlePlaceholderTarget.classList.toggle("hidden", open)
    }
  }
}
