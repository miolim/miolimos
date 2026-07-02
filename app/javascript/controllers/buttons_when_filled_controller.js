import { Controller } from "@hotwired/stimulus"

// #336 (Hans, 2026-05-24): Action-Buttons (Submit etc.) sind unsichtbar,
// solange das Eingabefeld leer ist; sobald Text drin steht, fadet das
// Actions-Element ein (= `hidden`-Klasse entfernt). Beim Leeren wieder
// hidden setzen.
//
// Markup-Konvention:
//   <form data-controller="buttons-when-filled"
//         data-action="input->buttons-when-filled#sync">
//     <textarea data-buttons-when-filled-target="input"></textarea>
//     <div class="hidden" data-buttons-when-filled-target="actions">
//       <button type="submit">…</button>
//     </div>
//   </form>
export default class extends Controller {
  static targets = ["input", "actions"]

  connect() {
    // Initial-State: actions hidden, wenn Input leer (server-Render hat
    // schon `hidden`-Markup). Sicherheitshalber einmal anwenden.
    this.sync()
  }

  sync() {
    if (!this.hasInputTarget || !this.hasActionsTarget) return
    const hasContent = (this.inputTarget.value || "").trim().length > 0
    this.actionsTarget.classList.toggle("hidden", !hasContent)
  }
}
