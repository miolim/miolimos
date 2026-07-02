import { Controller } from "@hotwired/stimulus"

// Mobile-Sandwich-Nav. Auf Desktop (md+) ist die Sidebar fest sichtbar
// (Tailwind-Klasse `md:translate-x-0`), auf Mobile wird sie per
// Transform-Shift ein-/ausgeblendet. Backdrop schließt beim Klick.
export default class extends Controller {
  static targets = ["sidebar", "backdrop"]

  toggle() {
    this.sidebarTarget.classList.toggle("-translate-x-full")
    this.backdropTarget.classList.toggle("hidden")
  }

  close() {
    this.sidebarTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
  }
}
