import { Controller } from "@hotwired/stimulus"

// #310: Wenn der Veroeffentlichen-Button geklickt wird, soll der
// aktuell im Edit-Textarea getippte Description-Text mit-gespeichert
// werden — sonst geht er verloren (Description-Blur-Submit ist seit
// #294 fuer Intra-Card-Klicks unterdrueckt, der Publish-Button sitzt
// in derselben Card, also feuert der Blur kein Submit).
//
// Strategie: auf submit-Event lesen wir das Description-Textarea aus
// und schreiben den aktuellen Wert in das hidden-Description-Field
// des Publish-Forms. Server-seitig wertet TaskMemberActions#publish
// dieses Feld zusaetzlich aus.
//
// Markup:
//   <form data-controller="capture-description"
//         data-action="submit->capture-description#sync">
//     <input type="hidden" name="description" value="…">
//     <button>Veroeffentlichen</button>
//   </form>
export default class extends Controller {
  sync(event) {
    const card = this.element.closest(".stack-card") || document
    // #438 (Hans, 2026-06-01): ZUERST die echte Beschreibungs-Textarea ueber
    // ihren description-toggle-Target greifen. Der frueher fuehrende
    // `textarea[name='description']`-Selektor traf im Task-Card faelschlich
    // die LEERE Description-Textarea der eingebetteten "Wartepunkt anlegen"-
    // Form (/create_awaiting) — capture stopfte dann "" ins Publish-Field,
    // der Server-#397-Guard uebersprang das Update, und der gerade getippte
    // Beschreibungstext ging beim Veroeffentlichen verloren. Bei aktivem CM6
    // ist die Textarea versteckt, ihr value wird aber von CM6 live gesynct.
    const ta = card.querySelector("textarea[data-description-toggle-target='input']") ||
               card.querySelector("textarea[name='task[description]']") ||
               card.querySelector("textarea[name='description']")
    if (ta) {
      const hidden = this.element.querySelector("input[type='hidden'][name='description']")
      if (hidden) hidden.value = ta.value
    }
    // #1010 (Hans): Gleiche Falle beim TITEL — der speichert nur onblur.
    // Wird mit Fokus im Titelfeld per Strg+Umschalt+Enter veroeffentlicht,
    // verliert das Publish-Rerender das Rennen gegen den Blur-PATCH und
    // zeigt den alten Titel. Daher den aktuell getippten Titel mitnehmen;
    // Server-Guard analog #397 (nur nicht-leer und geaendert).
    const titleField = card.querySelector("textarea[name='task[title]'], input[name='task[title]']")
    if (titleField) {
      const hiddenTitle = this.element.querySelector("input[type='hidden'][name='title']")
      if (hiddenTitle) hiddenTitle.value = titleField.value
    }
  }
}
