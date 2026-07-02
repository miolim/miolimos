import { Controller } from "@hotwired/stimulus"

// #239 Phase B+: Klick auf das „+"-Icon neben einem untyped Wikilink
// triggert die Server-seitige Body-Modifikation (^anchor einfuegen,
// Relation anlegen). Auf Erfolg: oeffnet sofort den Relation-Popover
// mit dem neuen anchor — der Body wird beim naechsten Re-Render mit
// dem stabilen Anchor versehen sein.
export default class extends Controller {
  static values = { sourceUuid: String, occurrence: Number }

  async start(event) {
    event.preventDefault()
    event.stopPropagation()
    try {
      const res = await fetch(this.typifyUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ occurrence: this.occurrenceValue })
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({}))
        alert(window.t("relation_typify.failed", { error: err.error || res.status }))
        return
      }
      const data = await res.json()
      this._openPopoverFor(data.anchor_id, data.target_title)
    } catch (err) {
      console.warn("typify error", err)
    }
  }

  get typifyUrl() {
    return `/knowledge_items/${encodeURIComponent(this.sourceUuidValue)}/relations/typify`
  }

  // Da das Wikilink im DOM noch das alte (untyped) Markup ist, koennen
  // wir den Relation-Popover-Controller nicht ueber das vorhandene Element
  // ansprechen. Wir bauen ein temporaeres Phantom-Element an der gleichen
  // Position, attachen den Controller dynamisch und triggern open. Beim
  // naechsten Body-Render (z.B. nach Save im Popover) ersetzt der Renderer
  // den Wikilink ohnehin durch die typed-Variante mit Relation-Indikator.
  _openPopoverFor(anchorId, _targetTitle) {
    const phantom = document.createElement("span")
    const rect = this.element.getBoundingClientRect()
    phantom.style.position = "fixed"
    phantom.style.top  = `${rect.bottom + window.scrollY}px`
    phantom.style.left = `${rect.left + window.scrollX}px`
    phantom.style.width  = "1px"
    phantom.style.height = "1px"
    phantom.style.pointerEvents = "none"
    phantom.setAttribute("data-controller", "relation-popover")
    phantom.setAttribute("data-relation-popover-source-uuid-value", this.sourceUuidValue)
    phantom.setAttribute("data-relation-popover-anchor-id-value", anchorId)
    document.body.appendChild(phantom)
    // Geben Stimulus einen Tick, den Controller zu attachen.
    setTimeout(() => {
      const ctrl = this.application.getControllerForElementAndIdentifier(phantom, "relation-popover")
      if (ctrl) {
        ctrl.open(new Event("click"))
      }
      // Phantom raeumen wir auf, wenn Popover wieder zu ist — sonst
      // bleibt's stehen, stoert aber nicht (pointer-events: none).
    }, 0)
  }
}
