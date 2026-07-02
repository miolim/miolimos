import { Controller } from "@hotwired/stimulus"

// #521 (Hans, 2026-06-06): Tab-Einrückung für Plain-Textareas.
//
// Standard-Browserverhalten: Tab in einer <textarea> verschiebt den Fokus
// zum nächsten Element (z.B. dem Speichern-Button). Beim Bearbeiten einer
// Antwort wollte Hans stattdessen eine Listen-Einrückung. Dieser Controller
// fängt Tab ab und rückt die aktuelle Zeile / Selektion um 2 Spaces ein,
// Shift+Tab rückt aus. Spiegelt CM6s `indentWithTab` für den Fall, dass
// CM6 nicht aktiv ist (Plain-Textarea-Editor).
//
// Verwendung: `data-controller="tab-indent"` direkt auf das <textarea>.
// Escape gibt den Fokus frei (Tab-Falle vermeiden — Accessibility): danach
// springt der nächste Tab wieder normal weiter.
const INDENT = "  "

export default class extends Controller {
  connect() {
    this._allowFocusEscape = false
    this._onKeydown = this._onKeydown.bind(this)
    this.element.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    this.element.removeEventListener("keydown", this._onKeydown)
  }

  _onKeydown(e) {
    if (e.key === "Escape") {
      // Eine Tab-Falle ist ein A11y-Problem: Escape erlaubt, dass der
      // nächste Tab den Fokus normal verlässt.
      this._allowFocusEscape = true
      return
    }
    if (e.key !== "Tab" || e.altKey || e.ctrlKey || e.metaKey) return
    if (this._allowFocusEscape) {
      this._allowFocusEscape = false
      return   // normales Tab-Verhalten (Fokuswechsel) durchlassen
    }
    e.preventDefault()

    const ta = this.element
    const v = ta.value
    const s = ta.selectionStart
    const en = ta.selectionEnd
    const lineStart = v.lastIndexOf("\n", s - 1) + 1

    if (s === en) {
      if (e.shiftKey) {
        const lead = v.slice(lineStart, s).match(/^ {1,2}/)
        if (!lead) return
        ta.value = v.slice(0, lineStart) + v.slice(lineStart + lead[0].length)
        const np = Math.max(lineStart, s - lead[0].length)
        ta.selectionStart = ta.selectionEnd = np
      } else {
        // Am Zeilenanfang einrücken (Listen-Item), Cursor mitführen.
        ta.value = v.slice(0, lineStart) + INDENT + v.slice(lineStart)
        ta.selectionStart = ta.selectionEnd = s + INDENT.length
      }
    } else {
      // Mehrzeilige Selektion: jede berührte Zeile ein-/ausrücken.
      const before = v.slice(0, lineStart)
      const sel = v.slice(lineStart, en)
      const after = v.slice(en)
      const newSel = e.shiftKey
        ? sel.replace(/^ {1,2}/gm, "")
        : sel.replace(/^/gm, INDENT)
      ta.value = before + newSel + after
      ta.selectionStart = lineStart
      ta.selectionEnd = lineStart + newSel.length
    }
    ta.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
