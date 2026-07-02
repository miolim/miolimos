import { Controller } from "@hotwired/stimulus"

// Macht eine Textarea so hoch wie ihr Inhalt — keine eigene Scrollbar
// mehr, kein doppelter Scroll. Outer-Container scrollt das ganze
// Detail-Panel als Einheit (inkl. Toolbar, Meta, Textarea).
//
// Markup:
//   <textarea data-controller="autosize" rows="6">…</textarea>
export default class extends Controller {
  connect() {
    this.element.style.overflowY = "hidden"
    this.element.style.resize    = "none"
    this._onInput = this.resize.bind(this)
    this.element.addEventListener("input", this._onInput)
    // Erste Anpassung — beim Connect ist scrollHeight schon korrekt.
    requestAnimationFrame(() => this.resize())
  }

  disconnect() {
    this.element.removeEventListener("input", this._onInput)
  }

  resize() {
    // Vor dem Reset auf `height: auto` die scroll-Position des
    // umgebenden Scroll-Containers merken. Sonst clamped der Browser
    // outer.scrollTop auf den temporär kleineren scrollHeight, und
    // wenn die Textarea wieder ihre echte Höhe annimmt, ist der
    // Scroll-Punkt für den User verloren — Cursor scheint dann
    // "irgendwohin" zu springen, obwohl nur die Textarea geblinkt hat.
    const outer = this.findScrollContainer()
    const saved = outer?.scrollTop
    this.element.style.height = "auto"

    // box-sizing: border-box (Tailwind-Default) — scrollHeight enthält
    // Padding, aber NICHT Border. Ohne Border-Aufschlag passt die
    // letzte Zeile minimal nicht mehr in den sichtbaren Bereich,
    // overflow:hidden clippt sie, und der Cursor in der letzten Zeile
    // sitzt halb außerhalb. Folge: Browser-Auto-Scroll verzettelt sich
    // und der User kann nicht ganz an die Ränder scrollen.
    const cs       = getComputedStyle(this.element)
    const isBorder = cs.boxSizing === "border-box"
    const borderY  = isBorder
      ? (parseFloat(cs.borderTopWidth) || 0) + (parseFloat(cs.borderBottomWidth) || 0)
      : 0
    this.element.style.height = `${this.element.scrollHeight + borderY}px`

    // Während des "height: auto"-Zwischenschritts kann der Browser die
    // Textarea intern scrollen, um den Cursor sichtbar zu halten. Mit
    // overflow:hidden ist das eigentlich nicht erlaubt, aber mindestens
    // Chrome setzt textarea.scrollTop trotzdem. Das Ergebnis: nach dem
    // Größen-Reset sind die obersten Zeilen unsichtbar verschoben —
    // jetzt zurücksetzen.
    this.element.scrollTop = 0

    if (outer && saved != null && outer.scrollTop !== saved) {
      outer.scrollTop = saved
    }
  }

  findScrollContainer() {
    let el = this.element.parentElement
    while (el) {
      const o = getComputedStyle(el).overflowY
      if (o === "auto" || o === "scroll") return el
      el = el.parentElement
    }
    return null
  }
}
