import { Controller } from "@hotwired/stimulus"

// #145: aktualisiert die Verknüpfungen-Zusammenfassung im Chevron-Header
// aus dem aktuellen DOM-Stand. Wird nach jedem Disclosure-Toggle
// aufgerufen, damit die Kurzfassung „2 Themen · 1 Quelle …" sofort
// stimmt — ohne dass die einzelnen Picker-Mutationen eigens den Header
// stream-replacen müssen.
//
// Counts kommen direkt aus dem DOM: jede Chips-Partial rendert ein
// Container-Div `task_<name>_chips_<id>` und packt die Chips als direkte
// Kinder rein; Wartepunkte/Anhänge tragen stabile CSS-Klassen.
export default class extends Controller {
  static targets = ["summary", "topics"]

  refresh() {
    // #458 (Hans, 2026-06-02): „Themen" nicht mehr als Zahl im Count-
    // Summary — sie werden separat mit Farbmarkierer gezeigt (renderTopics).
    const labels = [
      ["Anhang",        "Anhänge",        this.countByClass("task-attachments-list-item")],
      ["Wartepunkt",    "Wartepunkte",    this.countByClass("task-awaitings-list-item")],
      ["Blockierer",    "Blockierer",     this.countChips("dependencies") + this.countByClass("task-successors-list-item")],
      ["Unteraufgabe",  "Unteraufgaben",  this.countChips("subtasks")],
      ["Person/Org",    "Personen/Orgs",  this.countChips("contacts")],
      ["Wissen",        "Wissen",         this.countChips("knowledge")],
      ["Quelle",        "Quellen",        this.countChips("sources")]
    ]
    const parts = labels.filter(([,, n]) => n > 0).map(([s, p, n]) => `${n} ${n === 1 ? s : p}`)
    this.summaryTarget.textContent = parts.length ? "· " + parts.join(" · ") : ""
    this.renderTopics()
  }

  // #458: Themen-Marker (Farbpunkt + Name) aus den Topic-Chips im DOM
  // aufbauen — bleibt so auch nach Add/Remove eines Themas aktuell.
  renderTopics() {
    if (!this.hasTopicsTarget) return
    const chips = this.element.querySelector("[id^='task_topics_chips_']")
    const items = chips ? Array.from(chips.children) : []
    this.topicsTarget.innerHTML = items.map(chip => {
      const dot   = chip.querySelector('span[style*="background"]')
      const color = dot ? dot.style.background : "#94a3b8"
      let name = ""
      chip.childNodes.forEach(n => {
        if (n.nodeType === Node.TEXT_NODE && !name && n.textContent.trim()) name = n.textContent.trim()
      })
      return `<span class="inline-flex items-center gap-1">· <span class="inline-block w-2 h-2 rounded-full shrink-0" style="background:${color}"></span>${this._esc(name)}</span>`
    }).join(" ")
  }

  _esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  countChips(name) {
    const el = this.element.querySelector(`[id^='task_${name}_chips_']`)
    return el ? el.children.length : 0
  }

  countByClass(cls) {
    return this.element.querySelectorAll(`.${cls}`).length
  }
}
