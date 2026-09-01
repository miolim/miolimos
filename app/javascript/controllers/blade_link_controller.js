import { Controller } from "@hotwired/stimulus"
import { stackVorhanden } from "lib/blade_stack_present"

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

  // #1509 (aus immoos #1348 uebernommen). EINE Regel fuer alle Card-Aufrufe:
  //
  //   Klick                ersetzt alles rechts der aufrufenden Card
  //   Umschalt+Klick       ergaenzt rechts daneben
  //   Umschalt+Alt+Klick   ergaenzt links daneben
  //   Alt+Klick            haengt ans Stapel-Ende
  //   ist die Card schon offen: springen, egal was gedrueckt ist
  //
  // Cmd/Strg bleibt bewusst FREI — das gehoert dem Browser („in neuem Tab
  // oeffnen"). Bei uns war Strg bisher der Anhaengen-Modifier (#1151); das
  // aendert sich damit, und zwar zugunsten der Regel, die der Browser
  // ohnehin hat.
  static oeffnungsart(event) {
    if (event?.shiftKey && event?.altKey) return "links"
    if (event?.shiftKey) return "rechts"
    if (event?.altKey)   return "ende"
    return "ersetzen"
  }

  append(event) {
    // #163 Phase 6c: wenn die aktuelle Seite KEINEN blade-stack hat
    // (body hat dann die has-blade-stack-Klasse NICHT), lassen wir das
    // Default-Browser-Verhalten weiterlaufen — d.h. <a href="...">
    // navigiert normal, der Klick zaehlt nicht als Append-Trigger.
    // Damit kann tasks/_row.html.erb generell blade-link verwenden, und
    // auf Seiten ohne Stack faellt es auf full-page-Navigation zurueck.
    // #1496 (aus immoos #1302): die TATSACHE fragen, nicht den Merker —
    // die Body-Klasse kann eine sich trennende Alt-Instanz entfernt haben,
    // waehrend der Stapel steht.
    if (!stackVorhanden()) return
    // #1509: Cmd/Strg gehoert dem Browser — bei gedrueckter Taste fassen wir
    // den Klick gar nicht erst an, dann macht er sein Uebliches.
    if (event.metaKey || event.ctrlKey) return
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
        mode: this.modeValue || null,
        // #1509: Die Oeffnungsart kommt aus dem KLICK, nicht aus der Herkunft
        // des Elements. Ein Plus an einer Zeile bleibt „ergaenze rechts" —
        // es IST der Modifier fuer Finger.
        oeffnen: this.modeValue === "append_to_substack"
                   ? "rechts" : this.constructor.oeffnungsart(event),
        // #1509: Anker ist die aufrufende CARD — egal ob Liste oder Detail.
        quelleId: event.currentTarget.closest("article.stack-card")?.id || null
      }
    }))
  }
}
