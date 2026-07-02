import { Controller } from "@hotwired/stimulus"

// #364 (Hans, 2026-05-25): Klick auf den Work-Tree-Usage-Counter im
// Wissen-Tab → flasht alle Work-Tree-Eintraege dieser KI im aktuell
// offenen Topic-Blade (Work-Tree-Tab) auf.
//
// Param: `ki-uuid` (= die UUID der KI, fuer die alle data-ki-uuid-
// matches im Stack hervorgehoben werden sollen).
export default class extends Controller {
  flash(event) {
    const uuid = event.params.kiUuid
    if (!uuid) return
    // Treffer ueberall im Stack — alle work_tree-Tabs offener
    // Topic-Blades sind potentielle Targets.
    const rows = document.querySelectorAll(`[data-work-tree-target="node"][data-ki-uuid="${CSS.escape(uuid)}"]`)
    if (rows.length === 0) return
    rows.forEach((row, i) => {
      row.classList.add("bg-amber-100", "transition")
      // Erste Card ins Viewport scrollen.
      if (i === 0) row.scrollIntoView({ behavior: "smooth", block: "center" })
    })
    setTimeout(() => {
      rows.forEach(row => row.classList.remove("bg-amber-100"))
    }, 1600)
  }
}
