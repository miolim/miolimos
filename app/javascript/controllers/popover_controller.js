import { Controller } from "@hotwired/stimulus"

// Generischer Click-/Escape-getriggerter Popover mit Outside-Close.
//
// Markup-Konvention:
//   <div data-controller="popover">
//     <button data-action="click->popover#toggle">…</button>
//     <div data-popover-target="content" class="hidden …">…</div>
//   </div>
//
// Outside-Klick und Escape schließen das Popover. Klick im Popover
// bleibt offen — bei Navigations-Links wird die Seite ohnehin gewechselt.
export default class extends Controller {
  static targets = ["content"]
  // #260: fixed=true positioniert den Popover-Inhalt per position:fixed
  // an den Trigger — so wird er NICHT von einem overflow-Container
  // (z.B. der scrollbaren Blade-Card) abgeschnitten.
  static values  = { fixed: Boolean }

  connect() {
    this._onOutsideClick = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    this._onEscape = (event) => {
      if (event.key === "Escape") this.close()
    }
    this._onReposition = () => {
      if (!this.contentTarget.classList.contains("hidden")) this._positionFixed()
    }
  }

  disconnect() { this.close() }

  toggle(event) {
    event?.preventDefault()
    if (this.contentTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.contentTarget.classList.remove("hidden")
    if (this.fixedValue) {
      this._positionFixed()
      window.addEventListener("scroll", this._onReposition, true)
      window.addEventListener("resize", this._onReposition)
    }
    document.addEventListener("click", this._onOutsideClick, true)
    document.addEventListener("keydown", this._onEscape)
  }

  close() {
    this.contentTarget.classList.add("hidden")
    document.removeEventListener("click", this._onOutsideClick, true)
    document.removeEventListener("keydown", this._onEscape)
    if (this.fixedValue) {
      window.removeEventListener("scroll", this._onReposition, true)
      window.removeEventListener("resize", this._onReposition)
    }
  }

  // Popover-Inhalt per position:fixed direkt unter den Trigger legen.
  // Rechtskante buendig mit dem Trigger; klappt nach oben, wenn unten
  // kein Platz ist.
  _positionFixed() {
    const trigger = this.element.querySelector("[data-action*='popover#toggle']")
    if (!trigger) return
    const r = trigger.getBoundingClientRect()
    const c = this.contentTarget
    c.style.position = "fixed"
    c.style.margin   = "0"
    const ch = c.offsetHeight
    const cw = c.offsetWidth
    // Gewuenschte Viewport-Koordinaten (rechtsbuendig zum Trigger).
    const below = window.innerHeight - r.bottom
    let top  = (below < ch + 8 && r.top > ch + 8) ? r.top - ch - 4 : r.bottom + 4
    let left = r.right - cw
    // #549 (Hans): Ein Vorfahre mit transform/filter/backdrop-filter/
    // perspective/contain bildet den Containing-Block fuer position:fixed —
    // dann beziehen sich top/left NICHT auf den Viewport, sondern auf dessen
    // Box. Symptom: in einem Blade-Header mit backdrop-blur landet das Menue
    // weit daneben (scheinbar "kein Menue"). Offset herausrechnen.
    const cb = this._fixedContainingBlock()
    if (cb) {
      const b = cb.getBoundingClientRect()
      top  -= b.top
      left -= b.left
    }
    c.style.top   = `${Math.round(top)}px`
    c.style.left  = `${Math.round(left)}px`
    c.style.right = "auto"
  }

  // Naechster Vorfahre, der fuer position:fixed einen Containing-Block
  // aufspannt (statt des Viewports). Gibt null zurueck, wenn keiner existiert.
  _fixedContainingBlock() {
    let el = this.contentTarget.parentElement
    while (el && el !== document.documentElement) {
      const s = getComputedStyle(el)
      if ((s.transform && s.transform !== "none") ||
          (s.filter && s.filter !== "none") ||
          (s.backdropFilter && s.backdropFilter !== "none") ||
          (s.perspective && s.perspective !== "none") ||
          (s.willChange && /transform|filter|perspective/.test(s.willChange)) ||
          (s.contain && /paint|layout|strict|content/.test(s.contain))) {
        return el
      }
      el = el.parentElement
    }
    return null
  }
}
