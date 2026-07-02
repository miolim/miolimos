import { Controller } from "@hotwired/stimulus"

// Auto-Dismiss-Toast mit Hover-Pause. Nach `timeoutValue`-ms Inaktivität
// wird das Element entfernt; bei mouseenter/leave wird der Timer
// pausiert und wiederaufgenommen.
//
// Markup:
//   <div data-controller="toast" data-toast-timeout-value="6000"
//        data-action="mouseenter->toast#pause mouseleave->toast#resume">
//     …Inhalt…
//     <button data-action="click->toast#dismiss">×</button>
//   </div>
export default class extends Controller {
  static values = { timeout: { type: Number, default: 6000 } }

  connect() {
    this.startTimer()
  }

  disconnect() {
    this.clearTimer()
  }

  startTimer() {
    this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  clearTimer() {
    if (this.timer) { clearTimeout(this.timer); this.timer = null }
  }

  pause() {
    this.clearTimer()
  }

  resume() {
    if (!this.timer) this.startTimer()
  }

  dismiss() {
    this.clearTimer()
    this.element.classList.add("opacity-0", "translate-x-2")
    setTimeout(() => this.element.remove(), 200)
  }
}
