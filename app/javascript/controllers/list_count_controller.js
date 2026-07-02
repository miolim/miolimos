import { Controller } from "@hotwired/stimulus"

// Hält einen Counter-Span synchron mit der Anzahl der [data-task-id]-
// Kinder einer oder mehrerer Listen. MutationObserver feuert auch bei
// Drag-and-Drop und bei Turbo-Stream-Append/Replace.
//
// Markup (eine Liste):
//   <span data-controller="list-count"
//         data-list-count-list-ids-value='["tasks_section_today"]'>0</span>
//
// Markup (Summe über mehrere Listen):
//   <span data-controller="list-count"
//         data-list-count-list-ids-value='["tasks_section_inbox","tasks_section_today","tasks_section_soon","tasks_section_later"]'>0</span>
export default class extends Controller {
  static values = { listIds: Array }

  connect() {
    this.lists = this.listIdsValue.map(id => document.getElementById(id)).filter(Boolean)
    if (!this.lists.length) return
    this.update()
    this.observer = new MutationObserver(() => this.update())
    this.lists.forEach(list => this.observer.observe(list, { childList: true }))
  }

  disconnect() {
    this.observer?.disconnect()
  }

  update() {
    const total = this.lists.reduce(
      (sum, list) => sum + list.querySelectorAll(":scope > [data-task-id]").length,
      0
    )
    this.element.textContent = String(total)
  }
}
