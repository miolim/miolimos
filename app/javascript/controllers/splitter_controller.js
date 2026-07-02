import { Controller } from "@hotwired/stimulus"

// Zweispalten-Layout mit verschiebbarem Trennsteg. Linkes Pane ist
// flex-1, rechtes kriegt per JS einen fixen `flex-basis` + `width`.
// Mindest-Breiten werden per JS UND per CSS (max-width) erzwungen,
// damit auch gespeicherte Werte aus localStorage auf kleinen
// Viewports nicht aus dem Ruder laufen.
//
// Markup:
//   <div data-controller="splitter"
//        data-splitter-key-value="splitter.waiting"
//        class="hidden md:flex items-start">
//     <div class="flex-1 min-w-0">…list…</div>
//     <div data-splitter-target="handle"
//          data-action="pointerdown->splitter#startDrag"
//          class="w-1 bg-slate-200 hover:bg-emerald-400 cursor-col-resize
//                 shrink-0 self-stretch touch-none"></div>
//     <aside data-splitter-target="right" class="shrink-0">…detail…</aside>
//   </div>
export default class extends Controller {
  static targets = ["right", "handle"]
  static values  = {
    key: String,
    default: { type: Number, default: 448 },
    minLeft: { type: Number, default: 260 },
    minRight: { type: Number, default: 280 }
  }

  connect() {
    this.dragging = false
    this._onMove = this.onMove.bind(this)
    this._onUp   = this.onUp.bind(this)
    this._onResize = this.onResize.bind(this)
    window.addEventListener("resize", this._onResize)

    this.applyDesiredWidth()
  }

  disconnect() {
    window.removeEventListener("resize", this._onResize)
  }

  // Mobile (<md): wir machen kein Splitter-Layout, sondern lassen das
  // rechte Pane voll Breite über der/statt der Liste rendern. Inline-
  // Styles, die wir auf Desktop gesetzt haben, werden hier wieder
  // entfernt — sonst klemmt das aside auf 130px o.ä. fest.
  isDesktop() {
    return window.innerWidth >= 768
  }

  applyDesiredWidth() {
    if (!this.isDesktop()) {
      this.clearInlineWidth()
      return
    }
    const saved      = parseInt(localStorage.getItem(this.keyValue), 10)
    const requested  = (Number.isFinite(saved) && saved > 0) ? saved : this.defaultValue
    this.applyWidth(this.clamp(requested))
  }

  clearInlineWidth() {
    this.rightTarget.style.flexBasis = ""
    this.rightTarget.style.width     = ""
    this.rightTarget.style.maxWidth  = ""
  }

  // Clamp gegen aktuelle Container-Breite — nie breiter als
  // (container - minLeft), nie schmaler als minRight.
  clamp(px) {
    const rect = this.element.getBoundingClientRect()
    if (rect.width <= 0) return px
    const maxAllowed = Math.max(this.minRightValue, rect.width - this.minLeftValue)
    return Math.min(maxAllowed, Math.max(this.minRightValue, px))
  }

  applyWidth(px) {
    this.rightTarget.style.flexBasis = `${px}px`
    this.rightTarget.style.width     = `${px}px`
    this.rightTarget.style.maxWidth  = `calc(100% - ${this.minLeftValue}px)`
  }

  startDrag(event) {
    event.preventDefault()
    this.dragging = true
    document.body.style.cursor = "col-resize"
    document.body.style.userSelect = "none"
    window.addEventListener("pointermove", this._onMove)
    window.addEventListener("pointerup",   this._onUp, { once: true })
  }

  onMove(event) {
    if (!this.dragging) return
    const rect = this.element.getBoundingClientRect()
    const raw = rect.right - event.clientX
    this.applyWidth(this.clamp(raw))
  }

  onUp() {
    if (!this.dragging) return
    this.dragging = false
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
    window.removeEventListener("pointermove", this._onMove)
    const px = parseInt(this.rightTarget.style.flexBasis, 10)
    if (px) localStorage.setItem(this.keyValue, String(px))
  }

  // Viewport ändert sich → entweder Mobile-Mode aktivieren (inline-
  // Styles entfernen) oder die Width im Desktop-Mode neu clampen,
  // damit gespeicherte Breiten nicht größer als der neue Viewport
  // werden.
  onResize() {
    this.applyDesiredWidth()
  }
}
