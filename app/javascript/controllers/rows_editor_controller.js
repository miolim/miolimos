import { Controller } from "@hotwired/stimulus"

// Tabellen-Editor mit Add/Remove-Row. Beim Add wird ein <template>
// dupliziert und ans Ende gehängt; Remove entfernt die Zeile aus
// dem DOM. Das Form serialisiert beim Submit die übrigen Zeilen
// (Rails-Convention: `name="affiliations[][org]"` etc.).
//
// Markup:
//   <div data-controller="rows-editor">
//     <template data-rows-editor-target="template">
//       <tr> … <input name="affiliations[][org]" …> </tr>
//     </template>
//     <table>
//       <tbody data-rows-editor-target="rows">
//         <%= existing rows %>
//       </tbody>
//     </table>
//     <button data-action="click->rows-editor#add">+ Hinzufügen</button>
//   </div>
export default class extends Controller {
  static targets = ["template", "rows"]

  add(event) {
    event?.preventDefault()
    const fragment = this.templateTarget.content.cloneNode(true)
    this.rowsTarget.appendChild(fragment)
    // Fokus aufs erste Input der neuen Zeile, damit man sofort tippen kann.
    const lastRow = this.rowsTarget.lastElementChild
    lastRow?.querySelector("input, select, textarea")?.focus()
  }

  remove(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-row]")
    if (row) row.remove()
  }

  // #546 (Hans, 2026-06-08): Löschung bestätigen — aber nur für bereits
  // gespeicherte Zeilen (nicht-leeres id-Feld). Frische Leerzeilen werden
  // ohne Rückfrage entfernt.
  removeConfirm(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-row]")
    if (!row) return
    const idField  = row.querySelector("input[name$='[id]']")
    const existing = row.dataset.existing === "true" || (idField && idField.value)
    if (existing && !window.confirm(window.t("rows_editor.delete_confirm"))) return
    row.remove()
  }
}
