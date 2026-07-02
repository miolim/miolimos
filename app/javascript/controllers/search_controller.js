import { Controller } from "@hotwired/stimulus"

// Debounces the search input and submits the enclosing form
// (which is a Turbo Frame that lands in #search_results).
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.timeout = null
    // #280 follow-up: Auf Stack-Seiten verhindert blade-link das normale
    // Browser-Navigieren — d.h. ohne Turbo-Nav blieb der Suchergebnis-
    // Frame mit den alten Treffern stehen. Wir hoeren auf das gleiche
    // Append-Event und leeren Input + Ergebnis-Dropdown.
    this._onAppend = () => this.clear()
    window.addEventListener("blade-stack:append", this._onAppend)
  }

  disconnect() {
    if (this._onAppend) window.removeEventListener("blade-stack:append", this._onAppend)
  }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.element.closest("form").requestSubmit()
    }, 150)
  }

  clear() {
    if (this.hasInputTarget) this.inputTarget.value = ""
    const frame = document.getElementById("search_results")
    if (frame) frame.innerHTML = ""
  }
}
