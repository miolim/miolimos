import { Controller } from "@hotwired/stimulus"

// #365 Phase 2 (Hans, 2026-05-25): Hoover-Popup neben/unter einem
// Wikilink. Ersetzt den fest reservierten Inline-Indicator-Space.
// Bei mouseenter erscheint ein Floating-Bar mit einem Icon (+ fuer
// typify-relation, pencil-link fuer edit-relation); Klick aufs Icon
// triggert die jeweilige Action.
//
// Values:
//   kind         : "typify" | "edit-relation"
//   sourceUuid   : UUID der KI in der der Wikilink steht
//   occurrence   : (typify-Mode) 1-basierter Index dieses Wikilinks
//                  im Body — Server-Side bestimmt
//   anchorId     : (edit-relation) ^anchor-id der bestehenden Relation
export default class extends Controller {
  static values = {
    kind:       String,
    sourceUuid: String,
    occurrence: { type: Number, default: 0 },
    anchorId:   String
  }

  show(event) {
    if (this._hideTimer) { clearTimeout(this._hideTimer); this._hideTimer = null }
    if (this._bar) return  // schon offen
    const bar = document.createElement("div")
    bar.className = "wikilink-hoover-bar absolute z-30 bg-white border border-slate-200 rounded shadow-sm " +
                    "flex items-center text-slate-500 p-0.5"
    const button = document.createElement("button")
    button.type = "button"
    button.className = "p-1 hover:bg-emerald-50 hover:text-emerald-700 rounded cursor-pointer"
    button.innerHTML = this._iconSvg()
    button.title = this.kindValue === "typify"
      ? "Beziehung qualifizieren"
      : "Beziehung bearbeiten"
    button.addEventListener("click", (e) => this._handleClick(e))
    bar.appendChild(button)

    // Positionieren: direkt unter dem Wikilink, rechts an dessen Ende.
    const rect = this.element.getBoundingClientRect()
    bar.style.position = "fixed"
    bar.style.top  = `${rect.bottom + 2}px`
    bar.style.left = `${rect.right  + 2}px`
    document.body.appendChild(bar)
    this._bar = bar

    // Mouseenter/leave auf dem Bar selbst — schedule cancel + hide-on-leave.
    bar.addEventListener("mouseenter", () => {
      if (this._hideTimer) { clearTimeout(this._hideTimer); this._hideTimer = null }
    })
    bar.addEventListener("mouseleave", () => this.scheduleHide())
  }

  scheduleHide() {
    if (this._hideTimer) clearTimeout(this._hideTimer)
    this._hideTimer = setTimeout(() => this._removeBar(), 200)
  }

  _removeBar() {
    if (this._bar) {
      this._bar.remove()
      this._bar = null
    }
    if (this._hideTimer) { clearTimeout(this._hideTimer); this._hideTimer = null }
  }

  disconnect() {
    this._removeBar()
  }

  _handleClick(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.kindValue === "typify") {
      // POST /knowledge_items/:source/wikilink_typify mit occurrence
      // (analog dem alten relation-typify-Controller).
      this._triggerTypify()
    } else if (this.kindValue === "edit-relation") {
      // Phantom-Element → relation-popover#open (analog
      // backlinks_popover._openRelationPopover).
      this._openRelationPopover()
    }
  }

  async _triggerTypify() {
    // #372-Fix (Hans, 2026-05-25 21:10): Endpoint korrigiert —
    // existierende Route ist `/knowledge_items/:source_uuid/relations/typify`,
    // nicht `/wikilink_typify`. Siehe RelationsController#typify.
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const fd = new FormData()
    fd.append("occurrence", String(this.occurrenceValue))
    const res = await fetch(`/knowledge_items/${this.sourceUuidValue}/relations/typify`, {
      method: "POST",
      headers: { "X-CSRF-Token": csrf, "Accept": "application/json" },
      body: fd
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      console.warn("relations#typify failed:", res.status, err)
      return
    }
    const data = await res.json()
    if (!data.anchor_id) return
    this._openRelationPopover(data.anchor_id)
    this._removeBar()
  }

  _openRelationPopover(anchorIdOverride) {
    const anchorId = anchorIdOverride || this.anchorIdValue
    if (!anchorId) return
    const phantom = document.createElement("div")
    phantom.setAttribute("data-controller", "relation-popover")
    phantom.setAttribute("data-relation-popover-source-uuid-value", this.sourceUuidValue)
    phantom.setAttribute("data-relation-popover-anchor-id-value", anchorId)
    phantom.style.display = "none"
    document.body.appendChild(phantom)
    requestAnimationFrame(() => {
      const ctrl = this.application.getControllerForElementAndIdentifier(phantom, "relation-popover")
      if (ctrl && typeof ctrl.open === "function") {
        // synthetisches Event fuer open(event) — currentTarget = Wikilink.
        // #372-Fix2 (Hans, 2026-05-25 21:39): stopPropagation+target ergaenzt,
        // sonst wirft relation-popover#open einen TypeError.
        ctrl.open({
          preventDefault: () => {},
          stopPropagation: () => {},
          currentTarget: this.element,
          target: this.element
        })
      }
    })
  }

  _iconSvg() {
    const stroke = `stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"`
    const attrs  = `xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" class="w-3.5 h-3.5" ${stroke}`
    if (this.kindValue === "typify") {
      // Plus-Symbol
      return `<svg ${attrs}><path d="M5 12h14"/><path d="M12 5v14"/></svg>`
    }
    // Link-Symbol (Lucide link)
    return `<svg ${attrs}>` +
      `<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>` +
      `<path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>` +
      `</svg>`
  }
}
