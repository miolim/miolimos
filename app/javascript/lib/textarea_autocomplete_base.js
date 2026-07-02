import { Controller } from "@hotwired/stimulus"
import { caretCoordinates } from "controllers/caret_position"

// #564: gemeinsame Basis der Textarea-Trigger-Autocompletes (wikilink `[[`,
// cite `[@`). Vorher zwei ~85 % identische Controller, die unabhängig
// drifteten. Subklassen liefern NUR noch: Trigger-/Close-Token, Query-Guard,
// Item-Rendering und Einfüge-Semantik.
//
// Verhalten (unverändert, jetzt einmal implementiert):
// - Beim Trigger-Token öffnet eine Vorschlagsliste (fetch von urlValue?q=…),
//   Weitertippen filtert, Abbruch bei Newline/"]" (Subklasse kann erweitern).
// - ArrowUp/Down navigiert, Enter/Tab fügt ein, Escape schließt,
//   Klick außerhalb schließt, mousedown auf einen Eintrag wählt.
// - Dropdown sitzt fixed an der Caret-Position (Flip nach oben bei
//   Platzmangel) — nicht unter der ganzen Textarea (#Stack-Scrollbalken).
//
// Markup (identifier-agnostisch, X = registrierter Controller-Name):
//   <div data-controller="X" data-X-url-value="…">
//     <textarea data-X-target="input">…</textarea>
//     <ul data-X-target="list" class="hidden …"></ul>
//   </div>
export default class TextareaAutocompleteBase extends Controller {
  static targets = ["input", "list"]
  static values  = { url: String }

  // ─── Hooks der Subklassen ───────────────────────────────────────────
  triggerToken() { throw new Error("triggerToken() in Subklasse definieren") }
  // Token, dessen Vorkommen NACH dem Trigger den Link als geschlossen gilt.
  closeToken()   { return "]" }
  // Query-Abbruch (Subklasse kann verschärfen, super() mitnehmen).
  queryBlocked(query) { return /[\]\n]/.test(query) }
  // Inner-HTML eines <li> (escapeHtml selbst aufrufen!).
  renderItem(_item, _isActive) { throw new Error("renderItem() in Subklasse definieren") }
  // { text, cursorOffset } — cursorOffset relativ zum Text-Ende (0 = dahinter,
  // -1 = vor dem letzten Zeichen, z.B. vor dem schließenden ]).
  insertion(_item) { throw new Error("insertion() in Subklasse definieren") }

  // ─── Lifecycle ──────────────────────────────────────────────────────
  connect() {
    this.index       = 0
    this.suggestions = []
    this.openStart   = null     // Position des Triggers im Wert, wenn geöffnet
    this.fetchAbort  = null

    // #564: gebundene Referenzen MERKEN — die alten Controller riefen
    // removeEventListener mit einem frischen bind() auf, das nie löste
    // (Listener-Leak über Turbo-Navigationen).
    this._onInput    = this.onInput.bind(this)
    this._onKeyDown  = this.onKeyDown.bind(this)
    this._onDocClick = this.onDocClick.bind(this)
    this.inputTarget.addEventListener("input",   this._onInput)
    this.inputTarget.addEventListener("keydown", this._onKeyDown)
    document.addEventListener("click", this._onDocClick)
  }

  disconnect() {
    this.inputTarget?.removeEventListener("input",   this._onInput)
    this.inputTarget?.removeEventListener("keydown", this._onKeyDown)
    document.removeEventListener("click", this._onDocClick)
  }

  // ─── Trigger-Logik ──────────────────────────────────────────────────
  onInput() {
    const { value, selectionStart } = this.inputTarget
    const before = value.substring(0, selectionStart)

    // Letzter Trigger, der noch nicht geschlossen ist.
    const lastOpen  = before.lastIndexOf(this.triggerToken())
    const lastClose = before.lastIndexOf(this.closeToken())
    if (lastOpen === -1 || lastOpen < lastClose) {
      this.close()
      return
    }

    // Zeichen zwischen Trigger und Cursor = aktueller Suchbegriff.
    const query = before.substring(lastOpen + this.triggerToken().length)
    if (this.queryBlocked(query)) {
      this.close()
      return
    }

    this.openStart = lastOpen
    this.fetchSuggestions(query)
  }

  // #667: Subklassen können je Query Extra-Params beisteuern (z.B.
  // item_type-Filter bei `[[@`). Default: nichts.
  extraParams(_query) { return "" }

  async fetchSuggestions(query) {
    if (this.fetchAbort) this.fetchAbort.abort()
    this.fetchAbort = new AbortController()
    // #667: aktuelle Query merken, damit renderItem/insertion das
    // `@`-Präfix erkennen (sie bekommen die Query sonst nicht).
    this._lastQuery = query
    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(query)}${this.extraParams(query)}`
      const res = await fetch(url, {
        headers: { "Accept": "application/json" },
        signal:  this.fetchAbort.signal
      })
      if (!res.ok) { this.close(); return }
      const data = await res.json()
      this.suggestions = data.items || []
      this.index = 0
      this.render()
    } catch (err) {
      if (err.name !== "AbortError") console.warn(`${this.identifier} suggest:`, err)
    }
  }

  // ─── Rendering ──────────────────────────────────────────────────────
  render() {
    if (this.suggestions.length === 0) { this.close(); return }
    const html = this.suggestions.map((item, i) => `
      <li data-action="mousedown->${this.identifier}#pick"
          data-ac-index="${i}"
          class="px-3 py-1.5 text-sm cursor-pointer ${i === this.index ? 'bg-emerald-50 text-emerald-900' : 'hover:bg-slate-50'}">
        ${this.renderItem(item, i === this.index)}
      </li>
    `).join("")
    this.listTarget.innerHTML = html
    this.positionAtCaret()
    this.listTarget.classList.remove("hidden")
  }

  // Dropdown direkt unter (oder über) der Cursor-Position positionieren,
  // statt unter der gesamten Textarea — sonst entsteht im Stack-Mode mit
  // autosize-Textarea ein zweiter Scrollbalken weit unten.
  positionAtCaret() {
    const ta = this.inputTarget
    const c  = caretCoordinates(ta, ta.selectionEnd)
    const ul = this.listTarget
    ul.style.position = "fixed"
    const dropdownH = 280
    const below = c.top + c.height + 4
    const above = c.top - dropdownH - 4
    const flipUp = (window.innerHeight - below) < dropdownH && above > 0
    ul.style.top  = `${flipUp ? above : below}px`
    ul.style.left = `${c.left}px`
    ul.style.minWidth = "20rem"
  }

  close() {
    this.suggestions = []
    this.openStart   = null
    this.listTarget.classList.add("hidden")
    this.listTarget.innerHTML = ""
  }

  isOpen() { return this.openStart !== null && this.suggestions.length > 0 }

  // ─── Keyboard / Maus ────────────────────────────────────────────────
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
      this.insert(this.suggestions[this.index])
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  pick(event) {
    event.preventDefault()
    const i = parseInt(event.currentTarget.dataset.acIndex, 10)
    this.insert(this.suggestions[i])
  }

  onDocClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  // ─── Insertion ──────────────────────────────────────────────────────
  insert(item) {
    if (!item || this.openStart === null) return
    const { text, cursorOffset = 0 } = this.insertion(item)
    const value  = this.inputTarget.value
    const cursor = this.inputTarget.selectionStart
    const before = value.substring(0, this.openStart)
    const after  = value.substring(cursor)
    this.inputTarget.value = before + text + after
    const newCursor = before.length + text.length + cursorOffset
    this.inputTarget.setSelectionRange(newCursor, newCursor)
    this.inputTarget.focus()
    this.close()
  }

  // ─── Utils ──────────────────────────────────────────────────────────
  escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#039;")
  }
}
