import { Controller } from "@hotwired/stimulus"
import { stackVorhanden } from "lib/blade_stack_present"
import { grundart, oeffnungsart } from "lib/blade_open_menu"

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
  static values = { kind: String, id: String, anchor: String, mode: String, nurModifier: Boolean }

  // #1642 (Hans): EIN Modifier statt drei Kombinationen — Umschalt+Klick
  // oeffnet das Menue (lib/blade_open_menu), das die Oeffnungsart abfragt.
  // Die Alt-Kombinationen aus #1509 entfallen; Alt+Klick wirkt jetzt wie ein
  // schlichter Klick. Cmd/Strg gehoert weiter dem Browser.
  //
  //   Klick            ersetzt alles rechts der aufrufenden Card
  //   Umschalt+Klick   Menue: rechts ersetzen · links · rechts · ans Ende
  //   ist die Card schon offen: springen, egal was gedrueckt ist
  static grundart(event) {
    return grundart(event)
  }

  async append(event) {
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
    // #1509 Nachtrag (Hans): „Dann die Modifier fuer den Mausklick auf die
    // Sidebar uebertragen." Die Seitenleiste ist eine NAVIGATIONS-Liste: Ein
    // schlichter Klick soll dort weiter zur Seite fuehren, wie er es immer
    // getan hat. Nur mit gedrueckter Taste wird die Zeile zum Card-Aufruf.
    // Deshalb faellt „ersetzen" hier durch — ohne preventDefault, damit der
    // Link seine normale Navigation behaelt.
    if (this.nurModifierValue && grundart(event) === "ersetzen") return
    event.preventDefault()
    event.stopPropagation()
    if (!this.kindValue || !this.idValue) return
    // #1642: Bei Umschalt fragt das Menue erst, wohin. Abbruch (Escape,
    // Klick daneben) heisst: nichts tun.
    //
    // `currentTarget` NACH einem await ist null — das ausloesende Element
    // deshalb vorher festhalten.
    const ausloeser = event.currentTarget
    const art = this.modeValue === "append_to_substack" ? "rechts" : await oeffnungsart(event)
    if (!art || art === "browser") return
    // #163 Phase 6b: wenn der Klick AUS einer Listen-Blade kommt,
    // signalisieren wir das im Event-Detail; der blade-stack-Controller
    // collapsed dann die Source-Card.
    const sourceList = ausloeser?.closest("article.stack-card[data-uuid^='list:']")
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
        oeffnen: art,
        // #1509: Anker ist die aufrufende CARD — egal ob Liste oder Detail.
        quelleId: ausloeser?.closest("article.stack-card")?.id || null
      }
    }))
  }
}
