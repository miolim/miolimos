import { Controller } from "@hotwired/stimulus"

// #540 (Hans, 2026-06-07): Veröffentlicht man einen Antwort-Entwurf direkt mit
// Strg+Umschalt+Enter (ohne vorher mit Strg+Enter zu speichern), ging der
// gerade getippte Text verloren — das Publish-Form schickte nur `publish=1`,
// nicht den aktuellen Body. Analog zu capture-description: auf submit lesen wir
// die Edit-Textarea DIESER Antwort und schreiben ihren Wert ins hidden
// `body`-Feld des Publish-Forms, sodass der update-Controller ihn mitspeichert.
//
// Wichtig: auf DIESE Antwort scopen (nicht die ganze Stack-Card) — eine
// Aufgabe hat viele Antwort-Karten, jede mit eigener Edit-Textarea.
export default class extends Controller {
  sync(event) {
    const root = this.element.closest("[data-controller~='description-toggle']") ||
                 this.element.closest("li") ||
                 this.element.closest(".stack-card")
    if (!root) return
    const ta = root.querySelector("textarea[data-description-toggle-target='input']")
    if (!ta) return
    const hidden = this.element.querySelector("input[type='hidden'][name='body']")
    if (hidden) hidden.value = ta.value
  }
}
