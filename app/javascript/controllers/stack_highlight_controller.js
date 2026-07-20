import { Controller } from "@hotwired/stimulus"
import { BladeStackRoutes } from "lib/blade_stack_routes"

// #1057 (aus immoos #965, Hans): Einträge, die als Card im aktuellen
// Blade-Stack geöffnet sind, in der Liste bzw. der Quell-Card mit roter
// Schrift hervorheben. Rein clientseitig: beobachtet den DOM und toggelt die
// Klasse `stack-open` auf der Zeile, deren blade-link-Ziel gerade als
// `.stack-card[data-uuid]` offen ist. Seit #1067 ist das die einzige
// Kennzeichnung (Chevron/Bold sind weg).
//
// #1067: kind→stack-uuid kommt aus der EINEN Routing-Tabelle
// (lib/blade_stack_routes) statt aus einer zweiten Abbildung hier. Die alte
// Kopie kannte nur die Sonderfälle src/invoiceline/topic_list und leitete
// alles andere als `${kind}:${id}` ab — falsch für jedes kind, dessen Prefix
// den Unterstrich verliert (`inbox_item` → `inboxitem:`, `tree_focus` →
// `treefocus:`, `topic_props` → `topicprops:`, `tag_list` → `list:tag:`).
// Solche Zeilen wurden nie rot, obwohl die Card offen war.
function stackUuid(kind, id) {
  return BladeStackRoutes.forKind(kind, id)?.stackId || null
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
      // #1058 (aus immoos #1020 übernommen): verschachtelte Deeplinks (z.B. ein
      // Icon in einer klickbaren Zeile, das auf eine andere Card zielt) dürfen
      // die umgebende Zeile NICHT färben — Opt-out per data-stack-no-highlight.
      if (el.hasAttribute("data-stack-no-highlight")) return

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
