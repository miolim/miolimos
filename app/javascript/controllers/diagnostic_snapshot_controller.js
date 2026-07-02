import { Controller } from "@hotwired/stimulus"

// #339 (Hans, 2026-05-24): Diagnose-Snapshot-Knopf. Klick → Overlay mit
// JSON des aktuellen Blade-Stack-Zustands (container-Geometrie + alle
// Card-Geometrien + Sticky-Werte + Active/Collapsed-Flags). Hans
// screenshottet das Overlay, ich lese die Daten ab — ohne DevTools.
//
// Markup:
//   <button data-controller="diagnostic-snapshot"
//           data-action="click->diagnostic-snapshot#snapshot">...</button>
export default class extends Controller {
  snapshot(event) {
    event.preventDefault()
    const container = document.getElementById("blade_stack_container")
    const payload = container ? this._gather(container) : { error: "no blade_stack_container" }
    this._showOverlay(payload)
  }

  _gather(c) {
    const cRect = c.getBoundingClientRect()
    const cards = Array.from(c.querySelectorAll(".stack-card")).map((card, i) => {
      const r = card.getBoundingClientRect()
      return {
        i,
        uuid:        card.dataset.uuid,
        w:           Math.round(r.width),
        x:           Math.round(r.left - cRect.left),
        stickyLeft:  card.style.left,
        stickyRight: card.style.right,
        zIndex:      card.style.zIndex,
        active:      card.dataset.active === "true",
        collapsed:   card.dataset.collapsed === "true",
        currentTab:  card.dataset.currentTab || null,
        innerHTMLLen: card.innerHTML?.length || 0
      }
    })
    return {
      time: new Date().toISOString(),
      url: window.location.href,
      viewport: { w: window.innerWidth, h: window.innerHeight },
      container: {
        cw:  c.clientWidth,
        sw:  c.scrollWidth,
        sl:  c.scrollLeft,
        max: c.scrollWidth - c.clientWidth
      },
      cards
    }
  }

  _showOverlay(payload) {
    // Frueheres Overlay (falls vorhanden) entfernen, sonst stapeln.
    document.querySelectorAll(".diagnostic-snapshot-overlay").forEach(o => o.remove())

    const wrap = document.createElement("div")
    wrap.className = "diagnostic-snapshot-overlay fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4"

    const panel = document.createElement("div")
    panel.className = "bg-white rounded shadow-xl max-w-3xl w-full max-h-[90vh] overflow-auto p-4 relative"

    const close = document.createElement("button")
    close.type = "button"
    close.className = "absolute top-2 right-2 p-1 rounded text-slate-500 hover:bg-slate-100 hover:text-slate-900 cursor-pointer text-xl leading-none"
    close.textContent = "×"
    close.title = window.t("diagnostic.close")
    close.addEventListener("click", () => wrap.remove())

    const header = document.createElement("div")
    header.className = "flex items-center gap-3 mb-2"

    const heading = document.createElement("h3")
    heading.className = "text-sm font-semibold text-slate-700"
    heading.textContent = window.t("diagnostic.heading")

    // Hans-Request: Copy-to-Clipboard.
    const copy = document.createElement("button")
    copy.type = "button"
    copy.className = "ml-auto px-2 py-1 rounded text-xs bg-slate-700 text-white hover:bg-slate-800 cursor-pointer"
    copy.textContent = window.t("diagnostic.copy")
    copy.title = window.t("diagnostic.copy_title")

    const jsonText = JSON.stringify(payload, null, 2)
    copy.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(jsonText)
        copy.textContent = window.t("diagnostic.copied")
        setTimeout(() => { copy.textContent = window.t("diagnostic.copy") }, 1500)
      } catch (e) {
        copy.textContent = window.t("diagnostic.copy_error")
      }
    })

    header.appendChild(heading)
    header.appendChild(copy)

    const hint = document.createElement("p")
    hint.className = "text-xs text-slate-500 mb-2"
    hint.textContent = window.t("diagnostic.hint")

    const pre = document.createElement("pre")
    pre.className = "text-[11px] leading-snug font-mono bg-slate-50 border border-slate-200 rounded p-2 overflow-auto whitespace-pre-wrap"
    pre.textContent = jsonText

    panel.appendChild(close)
    panel.appendChild(header)
    panel.appendChild(hint)
    panel.appendChild(pre)
    wrap.appendChild(panel)
    document.body.appendChild(wrap)

    // Outside-Click + Esc schliessen.
    wrap.addEventListener("click", (e) => { if (e.target === wrap) wrap.remove() })
    const onKey = (e) => { if (e.key === "Escape") { wrap.remove(); document.removeEventListener("keydown", onKey) } }
    document.addEventListener("keydown", onKey)
  }
}
