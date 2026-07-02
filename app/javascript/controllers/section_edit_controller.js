import { Controller } from "@hotwired/stimulus"

// #546 (Hans, 2026-06-08): Section-weiter Umschalter zwischen Anzeige
// (read-only) und Edit-Formular einer Person/Org-Detail-Section. Der
// Hinzufügen- und der Bearbeiten-Befehl in der Titelzeile schalten auf
// Edit; Abbrechen/Speichern führen zurück zur Anzeige.
//
//   <section data-controller="section-edit">
//     <button data-action="click->section-edit#edit">Bearbeiten</button>
//     <div data-section-edit-target="display">…read-only…</div>
//     <form data-section-edit-target="edit" hidden>…inputs…</form>
//   </section>
export default class extends Controller {
  static targets = ["display", "edit"]

  edit(event) {
    event?.preventDefault()
    if (this.hasDisplayTarget) this.displayTarget.hidden = true
    if (this.hasEditTarget)    this.editTarget.hidden = false
  }

  cancel(event) {
    event?.preventDefault()
    if (this.hasEditTarget)    this.editTarget.hidden = true
    if (this.hasDisplayTarget) this.displayTarget.hidden = false
  }
}
