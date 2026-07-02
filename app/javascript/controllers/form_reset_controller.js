import { Controller } from "@hotwired/stimulus"

// #484 (Hans, 2026-06-03): setzt das Formular nach erfolgreichem Turbo-
// Submit zurueck — der Eingabeschlitz (z.B. Topic-Reiter-Quick-Add) ist
// danach wieder leer. Auf turbo:submit-end hoeren (Turbo resettet nicht
// von selbst).
//
//   <%= form_with …, data: { controller: "form-reset",
//                            action: "turbo:submit-end->form-reset#reset" } %>
export default class extends Controller {
  reset(event) {
    // Nur bei Erfolg leeren; bei Fehler den getippten Text stehen lassen.
    if (event.detail && event.detail.success === false) return
    this.element.reset?.()
  }
}
