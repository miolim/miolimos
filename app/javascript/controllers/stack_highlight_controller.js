import { Controller } from "@hotwired/stimulus"

// #1057 (aus immoos #965, Hans): Einträge, die als Card im aktuellen
// Blade-Stack geöffnet sind, in der Liste bzw. der Quell-Card mit roter
// Schrift hervorheben — zusätzlich zum Chevron. Rein clientseitig: beobachtet
// den DOM und toggelt die Klasse `stack-open` auf der Zeile, deren
// blade-link-Ziel gerade als `.stack-card[data-uuid]` offen ist.
//
// Eigene kind→stack-uuid-Abbildung analog zu lib/blade_stack_routes.js —
// bewusst nur die Fälle, deren Prefix nicht einfach `${kind}:` ist.
const PREFIX = {
  invoice_line: "invoiceline",
  source: "src",
  ki: null // KI-UUID ist die id selbst
}

function stackUuid(kind, id) {
  if (kind === "ki") return id
  if (kind === "topic_list") return `list:topic:${id}`
  const p = kind in PREFIX ? PREFIX[kind] : kind
  return p ? `${p}:${id}` : id
}

export default class extends Controller {
  connect() {
    this.observer = new MutationObserver(() => this.schedule())
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.refresh()
  }

  disconnect() {
    this.observer?.disconnect()
    if (this._raf) cancelAnimationFrame(this._raf)
  }

  schedule() {
    if (this._raf) return
    this._raf = requestAnimationFrame(() => { this._raf = null; this.refresh() })
  }

  refresh() {
    // Während des Umschaltens nicht selbst wieder triggern.
    this.observer?.disconnect()

    const open = new Set()
    this.element.querySelectorAll(".stack-card[data-uuid]").forEach(c => open.add(c.dataset.uuid))

    this.element.querySelectorAll("[data-blade-link-kind-value][data-blade-link-id-value]").forEach(el => {
      // Sidebar-Einträge bleiben unverändert (Hans, #965): dort keine rote Schrift.
      if (el.closest("aside")) return

      const uuid = stackUuid(el.dataset.bladeLinkKindValue, el.dataset.bladeLinkIdValue)
      let row = el.closest("li, form, tr") || el.parentElement || el
      // #965: In Drill-Down-Bäumen umschließt das <li> die aufgeklappten
      // Kind-Einträge (verschachtelte disclosure-Liste). Dann NUR die eigene
      // Zeile färben (den blade-link-Zeilenkörper) — sonst würden auch die
      // Kinder rot, obwohl sie nicht als Card offen sind.
      if (row.querySelector("[data-disclosure-target='content']")) row = el
      row.classList.toggle("stack-open", !!(uuid && open.has(uuid)))
    })

    this.observer?.observe(this.element, { childList: true, subtree: true })
  }
}
