import { Controller } from "@hotwired/stimulus"

// Markiert die Listen-Row, deren Detail gerade rechts angezeigt wird,
// per data-active="true" (CSS via data-[active=true]:… in den
// jeweiligen _row-Partials). Liest die aktive Entitäts-ID aus der
// URL und reagiert auf Turbo-Lifecycle-Events.
//
// Generisch über mehrere Entitätstypen — pro Pattern ein Selector,
// der aus dem ersten Capture (id oder slug) die Row im DOM findet.
const PATTERNS = [
  { regex: /^\/tasks\/(\d+)/,           selector: id => `#task_row_${id}`           },
  { regex: /^\/awaitings\/(\d+)/,       selector: id => `#awaiting_row_${id}`       },
  { regex: /^\/communications\/(\d+)/,  selector: id => `#communication_row_${id}`  },
  // Topic-Row hat numerische ID + data-topic-slug — URL ist Slug-basiert.
  { regex: /^\/topics\/([^/?#]+)/,      selector: slug => `[data-topic-slug="${CSS.escape(slug)}"]` },
  // Source-Row ist von Anfang an slug-basiert (`source_row_<slug>`).
  { regex: /^\/sources\/([^/?#]+)/,     selector: slug => `#source_row_${CSS.escape(slug)}` }
]

export default class extends Controller {
  connect() {
    this.boundUpdate = this.markFromUrl.bind(this)
    document.addEventListener("turbo:load",        this.boundUpdate)
    document.addEventListener("turbo:render",      this.boundUpdate)
    document.addEventListener("turbo:frame-load",  this.boundUpdate)
    window.addEventListener("popstate",            this.boundUpdate)
    this.markFromUrl()
  }

  disconnect() {
    document.removeEventListener("turbo:load",       this.boundUpdate)
    document.removeEventListener("turbo:render",     this.boundUpdate)
    document.removeEventListener("turbo:frame-load", this.boundUpdate)
    window.removeEventListener("popstate",           this.boundUpdate)
  }

  markFromUrl() {
    this.element.querySelectorAll("[data-active='true']").forEach(el => {
      el.dataset.active = "false"
    })
    const path = window.location.pathname
    for (const p of PATTERNS) {
      const m = path.match(p.regex)
      if (!m) continue
      const row = this.element.querySelector(p.selector(m[1]))
      if (row) {
        row.dataset.active = "true"
        return
      }
    }
  }
}
