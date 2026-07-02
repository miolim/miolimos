// #208: Backlinks-Popover als eigenstaendige Klasse. Vorher inline im
// paragraph_actions_controller.js; jetzt wiederverwendbar (z.B. fuer
// Source-/Topic-Backlinks, falls die mal kommen) und isoliert vom
// Stimulus-Lifecycle.
//
// Benutzung:
//
//   const popover = new BacklinksPopover({
//     uuid:                "knowledge-item-uuid",
//     onItemClick: (targetUuid, sourceCard) => { ... }
//   })
//   popover.open(anchorElement, "block-1")
//
// Die Klasse haelt KEINE Referenz auf den blade-stack-Controller —
// das Klick-Verhalten wird per Callback injiziert, damit das Modul
// frei von Stimulus-Abhaengigkeiten bleibt.
//
// #312 follow-up (Hans, 2026-05-23): pro Backlink-Eintrag ein
// Ketten-Icon — Klick typisiert den Wikilink (Block-Anker → Relation)
// und oeffnet den Relation-Popover. Nutzt einen frischen Stimulus-
// Application-Lookup analog zum relation_typify-Phantom-Trick.

const CHAIN_ICON_SVG =
  '<svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-3.5 h-3.5 align-middle" ' +
  'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
  'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
  '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>' +
  '<path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>'

export class BacklinksPopover {
  constructor({ uuid, onItemClick = null, application = null }) {
    this.uuid = uuid
    this.onItemClick = onItemClick
    this.application = application
  }

  async open(anchorEl, anchor) {
    // Frueheren Popover (falls noch offen) wegraeumen.
    document.querySelectorAll(".backlink-popover").forEach(p => p.remove())

    const res = await fetch(
      `/knowledge_items/${this.uuid}/backlinks?anchor=${encodeURIComponent(anchor)}`,
      { headers: { "Accept": "application/json" } }
    )
    if (!res.ok) return
    const data = await res.json()

    const pop = document.createElement("div")
    pop.className = "backlink-popover fixed z-50 bg-white border border-slate-200 rounded shadow-lg p-2 text-xs max-w-xs"
    if (!data.items?.length) {
      pop.innerHTML = `<p class="text-slate-500 italic">Keine Backlinks.</p>`
    } else {
      // #501 (Hans, 2026-06-04): Antwort-Quellen mit Parent-Titel + „: Antwort"
      // + passendem Icon (statt nackter UUID); Klick oeffnet die ganze
      // Aufgabe/KI (nav_uuid) und scrollt zur Antwort (scroll_to).
      const list = data.items.map(i => `
        <li class="flex items-center gap-1.5">
          <a href="#" data-target-uuid="${this._escape(i.uuid)}"
             data-nav-uuid="${this._escape(i.nav_uuid || i.uuid)}"
             data-scroll-to="${this._escape(i.scroll_to || "")}"
             class="backlink-popover-link inline-flex items-center gap-1 min-w-0 text-emerald-700 hover:underline flex-1">
             ${this._icon(i.icon)}<span class="truncate">${this._escape(i.label || i.title || i.uuid)}</span></a>
          <button type="button"
                  class="backlink-popover-typify text-slate-300 hover:text-emerald-600 shrink-0 cursor-pointer"
                  data-source-uuid="${this._escape(i.uuid)}"
                  title="Als Beziehung qualifizieren">${CHAIN_ICON_SVG}</button>
        </li>
      `).join("")
      pop.innerHTML = `<ul class="space-y-0.5">${list}</ul>`
    }

    const rect = anchorEl.getBoundingClientRect()
    pop.style.top  = `${rect.bottom + 4}px`
    pop.style.left = `${rect.left}px`
    document.body.appendChild(pop)

    if (this.onItemClick) {
      pop.querySelectorAll(".backlink-popover-link").forEach(a => {
        a.addEventListener("click", (e) => {
          e.preventDefault()
          e.stopPropagation()
          const navUuid  = a.dataset.navUuid || a.dataset.targetUuid
          const scrollTo = a.dataset.scrollTo || null
          if (!navUuid) return
          const sourceCard = anchorEl.closest("[data-uuid]")
          pop.remove()
          this.onItemClick({ navUuid, scrollTo, sourceCard })
        })
      })
    }

    // Ketten-Icon pro Entry — typify + Relation-Popover.
    pop.querySelectorAll(".backlink-popover-typify").forEach(btn => {
      btn.addEventListener("click", async (e) => {
        e.preventDefault()
        e.stopPropagation()
        const sourceUuid = btn.dataset.sourceUuid
        if (!sourceUuid) return
        await this._typifyAndOpenRelation(sourceUuid, anchor, btn)
      })
    })

    // Outside-Click schliesst den Popover. `capture: true` faengt den
    // Click bevor andere Handler ihn sehen — sonst koennte ein Stimulus-
    // Action den Popover schon wegraeumen, bevor dieser Handler greift.
    const close = (e) => {
      if (pop.contains(e.target)) return
      pop.remove()
      document.removeEventListener("click", close, true)
    }
    setTimeout(() => document.addEventListener("click", close, true), 0)
  }

  async _typifyAndOpenRelation(sourceUuid, targetAnchor, anchorEl) {
    // #312 follow-up (Hans-Modell): jede Block-Anker-Wikilink HAT
    // bereits eine Relation (RelationSync legt sie an, mit
    // target_block_anchor). Wir oeffnen direkt den Popover — kein
    // Typify-Call mehr noetig.
    this._openRelationPopover(sourceUuid, targetAnchor, anchorEl)
  }

  // Phantom-Element + Stimulus-Lookup, analog zu relation_typify_controller.
  _openRelationPopover(sourceUuid, anchorId, anchorEl) {
    if (!this.application) {
      console.warn("BacklinksPopover: keine Stimulus-Application → Relation-Popover nicht oeffenbar")
      return
    }
    const phantom = document.createElement("span")
    const rect = anchorEl.getBoundingClientRect()
    phantom.style.position = "fixed"
    phantom.style.top  = `${rect.bottom + window.scrollY}px`
    phantom.style.left = `${rect.left + window.scrollX}px`
    phantom.style.width  = "1px"
    phantom.style.height = "1px"
    phantom.style.pointerEvents = "none"
    phantom.setAttribute("data-controller", "relation-popover")
    phantom.setAttribute("data-relation-popover-source-uuid-value", sourceUuid)
    phantom.setAttribute("data-relation-popover-anchor-id-value", anchorId)
    document.body.appendChild(phantom)
    setTimeout(() => {
      const ctrl = this.application.getControllerForElementAndIdentifier(phantom, "relation-popover")
      if (ctrl) ctrl.open(new Event("click"))
    }, 0)
  }

  _escape(s) {
    return String(s).replace(/[&<>\"]/g, c => (
      { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]
    ))
  }

  // #501: kleines Inline-Icon je Quellen-Typ (Aufgabe vs. KI/Notiz).
  _icon(kind) {
    const cls = 'class="inline-block w-3.5 h-3.5 shrink-0 align-middle" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"'
    if (kind === "task") {
      // Checkliste/Aufgabe
      return `<svg xmlns="http://www.w3.org/2000/svg" ${cls}><path d="m3 17 2 2 4-4"/><path d="m3 7 2 2 4-4"/><path d="M13 6h8"/><path d="M13 12h8"/><path d="M13 18h8"/></svg>`
    }
    // KI/Notiz
    return `<svg xmlns="http://www.w3.org/2000/svg" ${cls}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M16 13H8"/><path d="M16 17H8"/></svg>`
  }
}
