import { Controller } from "@hotwired/stimulus"

// #343 (Hans, 2026-05-25): Drei-Stufen-Toggle pro Reference-Knoten.
// Cycle: 0 = nur Ueberschrift, 1 = Ueberschrift + erster Absatz,
//        2 = Ueberschrift + ganzer Inhalt → zurueck zu 0.
//
// Targets:
//   - icon:       Chevron, rotiert 0deg / 45deg / 90deg
//   - firstPara:  erster Absatz (visible bei state >= 1)
//   - fullRest:   restlicher Inhalt (visible bei state == 2)
//
// State wird als data-ref-cycle-state-value gehalten.
export default class extends Controller {
  static targets = ["icon", "firstPara", "fullRest"]
  static values  = { state: { type: Number, default: 0 } }

  connect() { this.apply() }

  cycle(event) {
    if (event) event.preventDefault()
    this.stateValue = (this.stateValue + 1) % 3
    this.apply()
  }

  apply() {
    const s = this.stateValue
    if (this.hasIconTarget) {
      this.iconTarget.classList.remove("rotate-0", "rotate-45", "rotate-90")
      this.iconTarget.classList.add(s === 0 ? "rotate-0" : s === 1 ? "rotate-45" : "rotate-90")
    }
    if (this.hasFirstParaTarget) this.firstParaTarget.classList.toggle("hidden", s < 1)
    if (this.hasFullRestTarget)  this.fullRestTarget.classList.toggle("hidden", s < 2)
  }
}
