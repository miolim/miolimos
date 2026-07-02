import { Controller } from "@hotwired/stimulus"

// #533 Phase 1c (Hans, 2026-06-07): Timer-Button auf einer Aufgaben-/KI-Card.
// Reiner Dispatcher — meldet dem Header-Timer (time-timer-Controller) den
// Start-Wunsch samt Subject (Aufgabe/KI) und dessen Topics. Der Header
// entscheidet dann nach Hans-Regel: genau 1 Topic → sofort starten;
// 0 oder mehrere → Popup mit Projekt-Wahl.
export default class extends Controller {
  static values = {
    subjectType: String,
    subjectId:   String,
    label:       String,
    topics:      Array
  }

  start(event) {
    event.preventDefault()
    window.dispatchEvent(new CustomEvent("time-timer:start-subject", {
      detail: {
        subjectType: this.subjectTypeValue,
        subjectId:   this.subjectIdValue,
        label:       this.labelValue,
        topics:      this.topicsValue || []
      }
    }))
  }
}
