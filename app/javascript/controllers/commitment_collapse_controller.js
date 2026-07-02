import { Controller } from "@hotwired/stimulus"

// #175: Wann-Icons-Reihe in der Aufgaben-Liste reagiert auf die
// tatsächlich verfügbare Breite der ROW (ResizeObserver). Auf schmaler
// Spalte (z.B. Split-Pane links) bleibt nur das aktive Icon sichtbar;
// Klick auf das aktive Icon klappt die anderen drei aus. Auf breitem
// Container sind ohnehin alle vier sichtbar — der Klick passiert dann
// als No-Op.
//
// Markup:
//   <span data-controller="commitment-collapse"
//         class="inline-flex items-center gap-0.5">
//     <button data-commitment-collapse-target="active" data-action="click->commitment-collapse#toggle">…</button>
//     <form  data-commitment-collapse-target="inactive">…</form>
//     <form  data-commitment-collapse-target="inactive">…</form>
//     <form  data-commitment-collapse-target="inactive">…</form>
//   </span>
//
// `threshold-value` ist die Container-Breite in px, ab der wir alle
// Icons zeigen. Darunter werden die nicht-aktiven Icons ausgeblendet,
// solange `expanded` false ist.
export default class extends Controller {
  static targets = ["inactive"]
  static values  = { threshold: { type: Number, default: 360 } }

  connect() {
    this.expanded = false
    // ResizeObserver auf der ROW (parent), nicht auf this.element —
    // die Wann-Icons-Span ist eng, der relevante Indikator ist die
    // verfügbare Listen-Spaltenbreite.
    const observed = this.element.closest("li") || this.element.parentElement || this.element
    this.observer = new ResizeObserver(() => this.applyVisibility(observed))
    this.observer.observe(observed)
    this.applyVisibility(observed)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  toggle(event) {
    // Im breiten Container ist Auf-/Zuklappen sinnlos (alles ist eh
    // sichtbar) — Klick fällt auf das `submit`-Verhalten der button
    // zurück, das es hier aber nicht gibt. Daher ein No-Op-Guard.
    if (!this.isCramped) return
    event?.preventDefault()
    this.expanded = !this.expanded
    this.applyToggle()
  }

  applyVisibility(observed) {
    this.isCramped = observed.offsetWidth < this.thresholdValue
    this.applyToggle()
  }

  applyToggle() {
    const show = !this.isCramped || this.expanded
    this.inactiveTargets.forEach(el => {
      el.style.display = show ? "" : "none"
    })
  }
}
