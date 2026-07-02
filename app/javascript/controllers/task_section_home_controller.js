import { Controller } from "@hotwired/stimulus"

// #232 (Hans, 2026-06-01): Section-Homing fuer Live-Updates der Task-Liste.
//
// Aendert sich die `commitment` einer Task, ersetzt der Modell-Broadcast die
// Row IN PLACE (im "tasks"-Stream) — sie bleibt damit zunaechst in ihrer alten
// Sektion stehen. Dieser Controller schiebt sie clientseitig in die zu ihrer
// neuen `data-section-key` passende Sektion. Das ist bewusst gezielt (kein
// Listen-Reload, der getippten Quickadd-Text zerstoeren wuerde) und
// modus-sicher: die `tasks_section_<key>`-Listen existieren nur in der
// Wann-Gruppierung; im Topic-Modus findet der Controller kein Ziel und laesst
// die Row in Ruhe (commitment bestimmt dort die Gruppierung nicht).
//
// Greift via MutationObserver auf den Sektionsbereich: jede neu eingefuegte/
// ersetzte Row wird einmal geprueft und ggf. umgehaengt. Die exakte
// Sortier-Position innerhalb der Sektion wird approximiert (prepend = oben,
// passt zur Default-Sortierung "neueste zuerst"); bei Spezial-Sortierung
// korrigiert sich die Position beim naechsten vollen Listen-Render.
export default class extends Controller {
  connect() {
    this._observer = new MutationObserver(muts => this._onMutations(muts))
    this._observer.observe(this.element, { childList: true, subtree: true })
    this._rehomeAll()
  }

  disconnect() {
    this._observer?.disconnect()
    this._observer = null
  }

  _onMutations(muts) {
    // Nur auf hinzugefuegte Element-Knoten reagieren (Replace/Prepend liefern
    // addedNodes). Eigene Move-Operationen sind idempotent (Section stimmt
    // danach), loesen also keine Endlosschleife aus.
    for (const m of muts) {
      for (const node of m.addedNodes) {
        if (node.nodeType !== 1) continue
        const row = node.matches?.("[data-task-id][data-section-key]")
          ? node
          : node.querySelector?.("[data-task-id][data-section-key]")
        if (row) this._rehome(row)
      }
    }
  }

  _rehomeAll() {
    this.element.querySelectorAll("[data-task-id][data-section-key]")
      .forEach(row => this._rehome(row))
  }

  _rehome(row) {
    const key = row.dataset.sectionKey
    if (!key) return
    const target = this.element.querySelector(`#tasks_section_${key}`)
    if (!target) return                       // Topic-Modus o.ae. -> nichts tun
    if (row.parentElement === target) return  // schon am richtigen Ort
    // Nur umhaengen, wenn die Row aktuell in EINER der Wann-Sektionen sitzt
    // (sonst ist es z.B. eine Subtask-Zeile in einer Disclosure -> in Ruhe).
    const currentSection = row.closest("ol[id^='tasks_section_']")
    if (!currentSection) return
    target.prepend(row)
  }
}
