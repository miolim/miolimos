import { Controller } from "@hotwired/stimulus"

// #163 Phase 4: Generischer „append-to-stack"-Trigger fuer Elemente
// AUSSERHALB des blade-stack-DOM-Teilbaums (insbesondere die Sidebar).
// Dispatched ein globales `blade-stack:append`-Event mit
// { kind, id }, das der blade_stack_controller auf window aufnimmt.
//
// Verwendung an einem <button>/<a>:
//   data-controller="blade-link"
//   data-blade-link-kind-value="topic"    // oder "task", "source"
//   data-blade-link-id-value="<slug-or-id>"
//   data-action="click->blade-link#append"
export default class extends Controller {
  static values = { kind: String, id: String, anchor: String, mode: String }

  append(event) {
    // #163 Phase 6c: wenn die aktuelle Seite KEINEN blade-stack hat
    // (body hat dann die has-blade-stack-Klasse NICHT), lassen wir das
    // Default-Browser-Verhalten weiterlaufen — d.h. <a href="...">
    // navigiert normal, der Klick zaehlt nicht als Append-Trigger.
    // Damit kann tasks/_row.html.erb generell blade-link verwenden, und
    // auf Seiten ohne Stack faellt es auf full-page-Navigation zurueck.
    if (!document.body.classList.contains("has-blade-stack")) return
    event.preventDefault()
    event.stopPropagation()
    if (!this.kindValue || !this.idValue) return
    // #163 Phase 6b: wenn der Klick AUS einer Listen-Blade kommt,
    // signalisieren wir das im Event-Detail; der blade-stack-Controller
    // collapsed dann die Source-Card.
    const sourceList = event.currentTarget.closest("article.stack-card[data-uuid^='list:']")
    window.dispatchEvent(new CustomEvent("blade-stack:append", {
      detail: {
        kind: this.kindValue,
        id: this.idValue,
        // #218: optionaler Anchor — z.B. "task_comment_354", damit das
        // blade-stack nach dem Append zur entsprechenden Stelle im
        // Card-Body scrollt.
        anchor: this.anchorValue || null,
        sourceListId: sourceList?.id || null,
        // #224 6f-2 cleanup: mode-Override. Default-Klick aus einer
        // Listen-Blade ist REPLACE_SUBSTACK; ein Plus-Icon kann hier
        // explizit "append_to_substack" anfordern.
        mode: this.modeValue || null
      }
    }))
  }
}
