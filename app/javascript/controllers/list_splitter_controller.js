import { Controller } from "@hotwired/stimulus"

// Splitter zwischen Wissens-Liste (links) und Stack-Bereich (rechts).
// Drag setzt die Liste-Breite per inline-Style; im collapsed-Modus
// (Streifen) verschwindet der Handle und die aside-Klasse `md:w-9`
// übernimmt. Wenn beim Drag unter `minLeft` gezogen wird, klappt die
// Liste automatisch zum Streifen via disclosure#collapseIfOpen.
export default class extends Controller {
  static targets = ["leftPane", "handle"]
  static values = {
    storageKey: String,
    default:    { type: Number, default: 288 },  // 18rem entspricht alter md:w-72
    minLeft:    { type: Number, default: 200 },  // unter Schwelle → collapse
    maxLeft:    { type: Number, default: 520 }
  }

  connect() {
    // Splitter und Streifen-Modus sind jetzt auch auf schmalen
    // Viewports aktiv (siehe disclosure_controller). Hier nur einen
    // resize-Listener, falls der Container überhaupt einen min-Width
    // unterschreitet.
    this._onResize = () => this.applyFromStorage()
    window.addEventListener("resize", this._onResize)

    this.applyFromStorage()

    this._onMove = this.onMove.bind(this)
    this._onUp   = this.onUp.bind(this)

    // Wenn der Disclosure-State sich ändert (Toggle vom User auf
    // dem Streifen oder vom Header-Chevron): inline-Width entweder
    // setzen (auf gespeicherten Wert) oder entfernen (damit md:w-9
    // greift). Ein MutationObserver auf data-collapsed reicht.
    this.attrObserver = new MutationObserver((muts) => {
      for (const m of muts) {
        if (m.attributeName === "data-collapsed") this.applyFromStorage()
      }
    })
    this.attrObserver.observe(this.leftPaneTarget, { attributes: true, attributeFilter: ["data-collapsed"] })
  }

  disconnect() {
    this.attrObserver?.disconnect()
    window.removeEventListener("resize", this._onResize)
  }

  isCollapsed() {
    return this.leftPaneTarget.dataset.collapsed === "true"
  }

  applyFromStorage() {
    // Im collapsed-Modus übernimmt die Tailwind-Klasse `data-[collapsed
    // =true]:w-9` die Breite — kein inline-Style.
    if (this.isCollapsed()) {
      this.leftPaneTarget.style.width     = ""
      this.leftPaneTarget.style.flexBasis = ""
      this.handleTarget.classList.add("hidden")
      return
    }
    const saved = parseInt(localStorage.getItem(this.storageKeyValue), 10)
    const w = (Number.isFinite(saved) && saved > 0) ? this.clamp(saved) : this.defaultValue
    this.applyWidth(w)
    this.handleTarget.classList.remove("hidden")
  }

  clamp(px) {
    return Math.min(this.maxLeftValue, Math.max(this.minLeftValue, px))
  }

  applyWidth(px) {
    this.leftPaneTarget.style.width     = `${px}px`
    this.leftPaneTarget.style.flexBasis = `${px}px`
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
    const raw = event.clientX - rect.left
    if (raw < this.minLeftValue) {
      // Unter Schwelle: zur Streifen-Variante kollabieren.
      this.endDrag()
      this.collapseList()
      return
    }
    this.applyWidth(Math.min(raw, this.maxLeftValue))
  }

  collapseList() {
    const ctl = window.Stimulus?.getControllerForElementAndIdentifier(this.leftPaneTarget, "disclosure")
    ctl?.collapseIfOpen()
  }

  onUp() { this.endDrag() }

  endDrag() {
    if (!this.dragging) return
    this.dragging = false
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
    window.removeEventListener("pointermove", this._onMove)
    const px = parseInt(this.leftPaneTarget.style.width, 10)
    if (px) localStorage.setItem(this.storageKeyValue, String(px))
  }
}
