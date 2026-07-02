import { Controller } from "@hotwired/stimulus"

// Toggle für zusätzliche Tabellen-Spalten in der KI-Liste (Creator,
// Erstelldatum). Setzt `data-cols-expanded="true|false"` aufs Outer-
// Element, sodass Tailwind-data-Variants (group-data-[cols-expanded=…])
// die neuen Spalten ein- bzw. ausblenden. Default ist collapsed; der
// Zustand wird in localStorage persistiert.
export default class extends Controller {
  static values = { storageKey: String }

  connect() {
    const stored = this.hasStorageKeyValue
      ? localStorage.getItem(this.storageKeyValue)
      : null
    this.element.dataset.colsExpanded = stored === "true" ? "true" : "false"
  }

  toggle() {
    const next = this.element.dataset.colsExpanded === "true" ? "false" : "true"
    this.element.dataset.colsExpanded = next
    if (this.hasStorageKeyValue) {
      localStorage.setItem(this.storageKeyValue, next)
    }
  }
}
