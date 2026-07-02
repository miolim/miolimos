import { Controller } from "@hotwired/stimulus"

// #704 (Hans, 2026-06-15): Interface-Kommunikationshilfe — ein
// „Beschriftungs-Modus". Schalter an: Mouse-Over hebt das Element/den
// Bereich hervor und zeigt dessen Label; Klick kopiert das Label in die
// Zwischenablage (statt die normale Aktion auszulösen). Erleichtert es,
// eindeutig zu beschreiben, wovon man gerade spricht.
//
// Angezeigt/kopiert wird ein Breadcrumb-Pfad der Vorfahren-Kette, z.B.
// „Hauptfenster > Blade > Spine > Schließen". Jede Ebene: data-ui-label >
// aria-label/title > bekannter Strukturname (#704 R2, Hans). ESC, erneuter
// Klick auf den Schalter oder das Tastenkürzel (Cmd/Ctrl+.) beenden.
export default class extends Controller {
  connect() {
    this._onOver  = this._onOver.bind(this)
    this._onMove  = this._onMove.bind(this)
    this._onClick = this._onClick.bind(this)
    this._onKey   = this._onKey.bind(this)
    this._onActivator = this._onActivator.bind(this)
    this.active = false
    document.addEventListener("keydown", this._onActivator, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onActivator, true)
    if (this.active) this._stop()
  }

  toggle() { this.active ? this._stop() : this._start() }

  // Cmd/Ctrl + .  schaltet den Modus überall um (Shortcut „egal", #704).
  _onActivator(e) {
    if (e.key === "." && (e.metaKey || e.ctrlKey)) {
      e.preventDefault()
      this.toggle()
    }
  }

  _start() {
    this.active = true
    document.documentElement.dataset.uiInspect = "on"
    this.element.classList.add("text-emerald-600", "bg-emerald-50")
    this.element.setAttribute("aria-pressed", "true")

    this._tip = document.createElement("div")
    this._tip.className = "fixed z-[9999] pointer-events-none px-2 py-1 rounded bg-slate-900 " +
      "text-white text-xs shadow-lg max-w-md leading-snug"
    this._tip.style.display = "none"
    document.body.appendChild(this._tip)

    document.addEventListener("pointerover", this._onOver, true)
    document.addEventListener("pointermove", this._onMove, true)
    document.addEventListener("click", this._onClick, true)
    document.addEventListener("keydown", this._onKey, true)
  }

  _stop() {
    this.active = false
    delete document.documentElement.dataset.uiInspect
    this.element.classList.remove("text-emerald-600", "bg-emerald-50")
    this.element.setAttribute("aria-pressed", "false")

    document.removeEventListener("pointerover", this._onOver, true)
    document.removeEventListener("pointermove", this._onMove, true)
    document.removeEventListener("click", this._onClick, true)
    document.removeEventListener("keydown", this._onKey, true)

    this._clearHighlight()
    this._tip?.remove()
    this._tip = null
    this._current = null
  }

  _onKey(e) {
    if (e.key === "Escape") { e.preventDefault(); this._stop() }
  }

  _onOver(e) {
    const found = this._labelFor(e.target)
    this._highlight(found.el)
    this._current = found
    if (this._tip) {
      this._tip.textContent = found.label
      this._tip.style.display = "block"
    }
  }

  _onMove(e) {
    if (!this._tip) return
    const pad = 14
    let x = e.clientX + pad, y = e.clientY + pad
    const r = this._tip.getBoundingClientRect()
    if (x + r.width > window.innerWidth)   x = e.clientX - r.width - pad
    if (y + r.height > window.innerHeight) y = e.clientY - r.height - pad
    this._tip.style.left = `${Math.max(0, x)}px`
    this._tip.style.top  = `${Math.max(0, y)}px`
  }

  _onClick(e) {
    // Klick auf den Schalter selbst NICHT abfangen (zum Ausschalten).
    if (this.element.contains(e.target)) return
    e.preventDefault()
    e.stopPropagation()
    e.stopImmediatePropagation()
    const label = (this._current && this._current.label) || this._labelFor(e.target).label
    this._copy(label)
  }

  async _copy(label) {
    try {
      await navigator.clipboard.writeText(label)
      this._toast(window.t("ui_inspector.copied", { label: label }))
    } catch (err) {
      this._toast(window.t("ui_inspector.copy_failed"))
    }
  }

  // #704 (Hans): Breadcrumb-Pfad statt Einzel-Label — die Vorfahren-Kette
  // von außen nach innen, z.B. „Hauptfenster > Blade > Spine > Schließen".
  // Jede Ebene liefert ihren Namen via data-ui-label > aria-label/title >
  // bekannter Strukturname; so werden auch unspezifische Elemente eindeutig.
  _labelFor(el) {
    const parts = []
    let node = el
    let leaf = null
    while (node && node.nodeType === 1 && node !== document.body) {
      // Strukturname VOR aria-label/title — sonst zeigt z.B. der Spine den
      // (redundanten) Blade-Titel statt „Spine" (#704 R3, Hans).
      let label = (node.dataset && node.dataset.uiLabel) ||
                  this._structuralName(node) ||
                  node.getAttribute("aria-label") ||
                  node.getAttribute("title")
      label = label && String(label).trim()
      if (label && parts[parts.length - 1] !== label) {
        if (!leaf) leaf = node
        parts.push(label)
      }
      node = node.parentElement
    }
    if (parts.length === 0) parts.push(this._derive(el))
    return { el: leaf || el, label: parts.reverse().join(" > ") }
  }

  // Bekannte Strukturelemente bekommen einen sprechenden Namen, ohne dass
  // jedes einzeln ein data-ui-label braucht.
  _structuralName(node) {
    if (!node.matches) return null
    if (node.matches("#blade_stack_container")) return window.t("ui_inspector.region_main_window")
    if (node.matches(".stack-card"))            return window.t("ui_inspector.region_card")
    if (node.matches(".stack-spine"))           return window.t("ui_inspector.region_spine")
    if (node.matches("turbo-frame"))            return null // Frames überspringen
    return null
  }

  _derive(el) {
    const host = el.closest && el.closest("[data-controller]")
    if (host) return host.dataset.controller.split(/\s+/)[0].replace(/[-_]/g, " ")
    return (el.id || (el.tagName || "element").toLowerCase())
  }

  _highlight(el) {
    if (this._hl === el) return
    this._clearHighlight()
    this._hl = el
    if (el && el.style) {
      this._prevOutline = el.style.outline
      this._prevOffset  = el.style.outlineOffset
      el.style.outline = "2px solid #10b981"
      el.style.outlineOffset = "-1px"
    }
  }

  _clearHighlight() {
    if (this._hl && this._hl.style) {
      this._hl.style.outline = this._prevOutline || ""
      this._hl.style.outlineOffset = this._prevOffset || ""
    }
    this._hl = null
  }

  _toast(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    const span = document.createElement("span")
    span.className = "flex-1 min-w-0"
    span.textContent = message
    const btn = document.createElement("button")
    btn.type = "button"
    btn.setAttribute("data-action", "click->toast#dismiss")
    btn.className = "text-slate-400 hover:text-white text-lg leading-none"
    btn.textContent = "×"
    div.append(span, btn)
    stack.appendChild(div)
  }
}
