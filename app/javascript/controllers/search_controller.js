import { Controller } from "@hotwired/stimulus"
import { stackVorhanden } from "lib/blade_stack_present"

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

  // #1321 (Hans, 2026-08-07): Enter im Suchfeld öffnet die vollständige
  // Ergebnis-Card, statt das Dropdown noch einmal zu submitten. Auf einer
  // Stack-Seite haengt sie sich an den aktuellen Stack; sonst bauen wir den
  // Stack auf dem Dashboard auf (gleiche Fallback-Logik wie blade-link).
  // Das Leeren des Felds erledigt der blade-stack:append-Listener oben.
  openAll(event) {
    const q = this.hasInputTarget ? this.inputTarget.value.trim() : ""
    if (q.length < 2) return
    event.preventDefault()
    clearTimeout(this.timeout)
    const payload = this.constructor.payloadFor(q)
    if (stackVorhanden()) {   // #1496 (aus immoos #1302)
      window.dispatchEvent(new CustomEvent("blade-stack:append", {
        detail: { kind: "search_list", id: payload }
      }))
    } else {
      const stack = encodeURIComponent(`list:dashboard,list:search:${payload}`)
      const url   = `/dashboard?stack=${stack}`
      if (window.Turbo) window.Turbo.visit(url); else window.location.href = url
    }
  }

  // base64url(suchbegriff), ohne Padding — muss zeichengleich zu
  // SearchQuery.encode_payload (Ruby) sein, sonst findet der Server die
  // Stack-Id nicht wieder. btoa kann nur Latin-1, deshalb der Umweg ueber
  // die UTF-8-Bytes (Umlaute!).
  static payloadFor(text) {
    const bytes = new TextEncoder().encode(text)
    let binary = ""
    bytes.forEach(b => { binary += String.fromCharCode(b) })
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  }

  clear() {
    if (this.hasInputTarget) this.inputTarget.value = ""
    const frame = document.getElementById("search_results")
    if (frame) frame.innerHTML = ""
  }
}
