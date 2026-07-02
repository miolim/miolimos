import { Controller } from "@hotwired/stimulus"

// Inline-Edit: Klick auf Display → zeigt das Formular, auto-submit beim blur.
// Verwendung:
//   <div data-controller="inline-edit">
//     <span data-inline-edit-target="display" data-action="click->inline-edit#edit">Titel</span>
//     <form data-inline-edit-target="form" hidden>
//       <input data-inline-edit-target="input" data-action="blur->inline-edit#save" />
//     </form>
//   </div>
export default class extends Controller {
  static targets = ["display", "form", "input"]

  edit() {
    this.displayTarget.hidden = true
    this.formTarget.hidden = false
    this.inputTarget.focus()
    this.inputTarget.select?.()
  }

  save() {
    this.formTarget.requestSubmit()
  }
}
