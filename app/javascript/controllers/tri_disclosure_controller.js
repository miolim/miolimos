import { Controller } from "@hotwired/stimulus"

// #581: Drei-Stufen-Disclosure für die Quellen-Details:
//   closed → filled (nur Felder mit Daten) → all (alle Felder) → closed
// Felder (oder beliebige Elemente) im Content tragen data-empty="true",
// wenn sie ohne Daten sind — im filled-Zustand werden sie versteckt.
// Optional localStorage-Persistenz über storage-key (wie disclosure).
//
// Nach einem Frame-Replace (Inline-Save rendert die Section neu) feuert
// connect() erneut und wendet den gespeicherten Zustand wieder an;
// data-empty kommt dabei frisch vom Server, ein gerade befülltes Feld
// bleibt also sichtbar.
export default class extends Controller {
  static targets = ["content", "icon", "label"]
  static values  = { storageKey: String }

  static STATES = ["closed", "filled", "all"]
  static LABELS = { closed: "", filled: "belegte Felder", all: "alle Felder" }

  connect() {
    let stored = this.hasStorageKeyValue ? localStorage.getItem(this.storageKeyValue) : null
    // Legacy-Migration: dieselben storage-keys hielten vorher die
    // disclosure-Bools ("true" = collapsed, "false" = open).
    if (stored === "true")  stored = "closed"
    if (stored === "false") stored = "all"
    this.apply(this.constructor.STATES.includes(stored) ? stored : "closed")
  }

  cycle() {
    const order = this.constructor.STATES
    const next  = order[(order.indexOf(this.state) + 1) % order.length]
    this.apply(next)
    if (this.hasStorageKeyValue) localStorage.setItem(this.storageKeyValue, next)
    // Kompatibel zum disclosure-Event (#145): Summary-Controller
    // (task-fields-summary etc.) berechnen ihre Spans nach jedem Toggle neu.
    this.dispatch("toggled", { detail: { collapsed: this.state === "closed", state: this.state } })
    this._flashSection()
  }

  // #589: Rahmen-Blitz bei jedem Toggle — Klasse neu starten (Reflow
  // dazwischen, sonst startet die CSS-Animation nicht erneut).
  _flashSection() {
    this.element.classList.remove("section-flash")
    void this.element.offsetWidth
    this.element.classList.add("section-flash")
  }

  // #581-Folge (Hans): Stufe 2 = 45°, Stufe 3 = 90° — so sind die beiden
  // offenen Stufen optisch unterscheidbar (zu bleibt 0°).
  static ROTATIONS = { closed: "", filled: "rotate(45deg)", all: "rotate(90deg)" }

  apply(state) {
    this.state = state
    this.element.dataset.state = state
    this.contentTarget.classList.toggle("hidden", state === "closed")
    if (this.hasIconTarget)  this.iconTarget.style.transform = this.constructor.ROTATIONS[state]
    if (this.hasLabelTarget) this.labelTarget.textContent = this.constructor.LABELS[state]
    this.contentTarget.querySelectorAll("[data-empty='true']").forEach(el => {
      el.classList.toggle("hidden", state === "filled")
    })
  }
}
