import { Controller } from "@hotwired/stimulus"
import { sichtbaresItem } from "lib/autocomplete_auswahl"

// Basis-Controller für Autocomplete-Felder, die ein JSON-Endpoint
// abfragen und eine Dropdown-Liste rendern. Abstrahiert Keyboard-
// Navigation, Fetch-Abort, Listen-Rendering, Blur-Schließen.
//
// Subklassen überschreiben:
//   - queryFromInput() → String, der an den Endpoint geschickt wird
//     (Default: inputTarget.value.trim() — reicht für Volltitel-Picker)
//   - renderItem(item, isActive) → HTML-String für eine Zeile
//   - commit(item) → was passiert bei Auswahl (Input setzen, Form submitten, …)
//
// Erwartetes JSON vom Endpoint: `{ items: [...] }`.
export default class extends Controller {
  static targets = ["input", "list"]
  static values  = { url: String }

  connect() {
    this.suggestions = []
    this.index       = 0
    this.fetchAbort  = null

    this.inputTarget.addEventListener("input",   this.onInput.bind(this))
    this.inputTarget.addEventListener("focus",   this.onInput.bind(this))
    this.inputTarget.addEventListener("keydown", this.onKeyDown.bind(this))
    this.inputTarget.addEventListener("blur",    this.onBlur.bind(this))
  }

  // Subklassen können das überschreiben, z.B. um nur das Segment nach
  // dem letzten Komma als Query zu verwenden (slug-autocomplete).
  queryFromInput() {
    return this.inputTarget.value.trim()
  }

  // Subklassen überschreiben das pro Item-Typ. `isActive` ist true für
  // die aktuell hervorgehobene Zeile (Pfeiltasten).
  renderItem(item, isActive) {
    const cls = isActive ? "bg-emerald-50 text-emerald-900" : "hover:bg-slate-50"
    return `<li class="px-3 py-1.5 text-sm cursor-pointer ${cls}">${this.escapeHtml(item.label || "")}</li>`
  }

  // Subklassen setzen hier den eigentlichen Wert (Hidden-Field, Segment,
  // …) und submitten ggf. das Formular.
  commit(_item) {
    throw new Error("Subclass must implement commit(item)")
  }

  // ─── Standardisierter Fetch + Keyboard + Rendering ──────────────────

  async onInput() {
    const q = this.queryFromInput()
    if (this.fetchAbort) this.fetchAbort.abort()
    this.fetchAbort = new AbortController()

    try {
      const url = `${this.urlValue}${this.urlValue.includes("?") ? "&" : "?"}q=${encodeURIComponent(q)}`
      const res = await fetch(url, {
        headers: { "Accept": "application/json" },
        signal: this.fetchAbort.signal
      })
      if (!res.ok) { this.close(); return }
      const data = await res.json()
      this.suggestions = data.items || []
      this.index = 0
      this.render()
    } catch (err) {
      if (err.name !== "AbortError") console.warn("autocomplete:", err)
    }
  }

  render() {
    if (this.suggestions.length === 0) { this.close(); return }
    // #1677 (aus immoOS 6ad257b6 uebernommen): Was der Nutzer SIEHT, wird hier eingefroren. `pick` und
    // Enter lasen bisher `this.suggestions[i]` — trifft zwischen Anzeige und
    // Klick eine neue Suchantwort ein, zeigt derselbe Index dann auf eine
    // ANDEREN Eintrag oder ins Leere. Der Klick wählte also still den falschen
    // Eintrag oder gar nichts (im Fork zweimal als „flatterhafter" Systemtest
    // aufgetreten — es war kein Flattern, es war dieser Fehler).
    this.rendered = this.suggestions.slice()
    this.listTarget.innerHTML = this.rendered
      .map((item, i) => this.wrapItem(item, i))
      .join("")
    this.listTarget.classList.remove("hidden")
  }

  // Der Eintrag, der an Position i WIRKLICH in der Liste steht.
  sichtbaresItem(i) {
    return sichtbaresItem(this.rendered, this.suggestions, i)
  }

  wrapItem(item, i) {
    // Klick via mousedown (damit Blur den mousedown noch zulässt).
    // data-autocomplete-index für pick(event).
    const inner = this.renderItem(item, i === this.index)
    // Wenn renderItem schon ein <li> liefert, umwickeln wir es nicht
    // doppelt — wir fügen nur das Action-Attribut ein.
    return inner.replace(/^<li/, `<li data-action="mousedown->${this.identifier}#pick" data-autocomplete-index="${i}"`)
  }

  close() {
    this.suggestions = []
    // `rendered` bleibt ABSICHTLICH stehen: Zwischen mousedown auf einem
    // Vorschlag und dessen Verarbeitung kann der Blur-Timer schließen — dann
    // wäre die Auswahl weg, obwohl der Nutzer sie gerade getroffen hat.
    // Ausgelöst wird `pick` ohnehin nur von einem Listeneintrag, den es dann
    // noch gibt.
    this.listTarget.classList.add("hidden")
    this.listTarget.innerHTML = ""
  }

  isOpen() {
    return this.suggestions.length > 0 && !this.listTarget.classList.contains("hidden")
  }

  onKeyDown(event) {
    if (!this.isOpen()) return
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.index = (this.index + 1) % this.suggestions.length
      this.render()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.index = (this.index - 1 + this.suggestions.length) % this.suggestions.length
      this.render()
    } else if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault()
      this.commit(this.sichtbaresItem(this.index))
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  pick(event) {
    event.preventDefault()
    const i = parseInt(event.currentTarget.dataset.autocompleteIndex, 10)
    this.commit(this.sichtbaresItem(i))
  }

  onBlur() {
    // Kurz verzögern, damit mousedown auf einem Listen-Eintrag
    // noch durchkommt.
    setTimeout(() => this.close(), 150)
  }

  escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }
}
