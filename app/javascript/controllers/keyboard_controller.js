import { Controller } from "@hotwired/stimulus"

// Globales Tastenkürzel: Cmd/Ctrl+K fokussiert die Suche.
// In die Top-Bar einhängen via data-controller="keyboard".
export default class extends Controller {
  connect() {
    this.onKey = this.onKey.bind(this)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
  }

  onKey(event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      const field = document.querySelector("input[type='search']")
      if (field) field.focus()
    }
  }
}
