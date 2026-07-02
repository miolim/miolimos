import { Controller } from "@hotwired/stimulus"

// #178: Wenn Hans während des Kommentar-Tippens wegnavigiert (Turbo-
// Visit, Tab-Wechsel, Reload), darf der Text nicht verloren gehen.
// Auto-Save als Entwurf via sendBeacon — kein UX-Stört-Dialog, der
// Datensatz landet still im Thread und ist beim Wiederkommen via
// „Veröffentlichen "-Button publishbar (#167).
//
// Markup-Konvention:
//   <form data-controller="comment-autosave"
//         data-comment-autosave-url-value="<%= task_comments_path(task) %>">
//     <textarea data-comment-autosave-target="input"></textarea>
//   </form>
export default class extends Controller {
  static targets = ["input"]
  static values  = { url: String }

  connect() {
    this.initialValue = this.inputTarget.value || ""
    // #181: Wenn das eigentliche Submit gerade lief, darf der
    // disconnect-Save NICHT mehr feuern — sonst doppelt der Server-
    // Antwort-Turbo-Stream-Replace die Form ersetzen UND wir hängen
    // einen zweiten Eintrag als Entwurf hinterher.
    this.submitted = false
    this.onBeforeVisit  = this.onBeforeVisit.bind(this)
    this.onBeforeUnload = this.onBeforeUnload.bind(this)
    this.onSubmitEnd    = this.onSubmitEnd.bind(this)
    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    window.addEventListener("beforeunload", this.onBeforeUnload)
    // submit-start signalisiert, dass Hans gerade den Posten/Entwurf-
    // Knopf gedrückt hat. Ab da kein zusätzlicher Auto-Save mehr.
    this.element.addEventListener("turbo:submit-start", this.onSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    this.element.removeEventListener("turbo:submit-start", this.onSubmitEnd)
    // Final-Save bei Turbo-Frame-Replace o.ä. — aber nicht, wenn der
    // Form-Inhalt gerade per Submit auf den Server gegangen ist.
    if (!this.submitted) this.saveIfChanged()
  }

  onSubmitEnd() { this.submitted = true }

  onBeforeVisit()  { this.saveIfChanged() }
  onBeforeUnload() { this.saveIfChanged() }

  saveIfChanged() {
    if (this.submitted) return
    const body = (this.inputTarget?.value || "").trim()
    if (!body) return
    if (body === this.initialValue.trim()) return
    if (!this.urlValue) return
    if (!navigator.sendBeacon) return

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const data = new URLSearchParams()
    data.append("body", body)
    data.append("as_draft", "1")
    if (token) data.append("authenticity_token", token)
    const blob = new Blob([data.toString()], { type: "application/x-www-form-urlencoded" })
    navigator.sendBeacon(this.urlValue, blob)
    // initialValue auffrischen, damit ein zweiter Save innerhalb desselben
    // Tab-Lebens nicht denselben Inhalt nochmal als zweiter Draft anlegt.
    this.initialValue = body
  }
}
