import { Controller } from "@hotwired/stimulus"

// #599: Inhalt-Toggle für KI-Listen — Alle | Nur Titel | Mit Inhalt.
// Zeilen tragen data-has-body="true|false"; der Toggle blendet die
// jeweils andere Gruppe aus. Sitzt als Zusatz-Controller auf der
// Tab-Section (tab_shell controllers-Local).
export default class extends Controller {
  static targets = ["btn"]

  connect() { this._mode = "alle" }

  filter(event) {
    this._mode = event.params.mode || "alle"
    this.element.querySelectorAll("[data-has-body]").forEach(row => {
      const has = row.dataset.hasBody === "true"
      const hide = (this._mode === "titel" && has) || (this._mode === "inhalt" && !has)
      row.classList.toggle("hidden", hide)
    })
    this.btnTargets.forEach(b => {
      const active = b.dataset.contentFilterModeParam === this._mode
      b.classList.toggle("bg-slate-700", active)
      b.classList.toggle("text-white", active)
      b.classList.toggle("text-slate-600", !active)
    })
    // #599-Folge: den angezeigt/gesamt-Zaehler der Befehlszeile nachziehen
    // (list-search sitzt auf derselben Section).
    const ls = this.application.getControllerForElementAndIdentifier(this.element, "list-search")
    ls?._updateCount?.()
  }
}
