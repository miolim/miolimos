import { Controller } from "@hotwired/stimulus"

// #306 (Hans): Schlankes Listen-Suchfeld. Tippt der User, werden Rows
// im benannten Item-Selector ausgeblendet, deren sichtbarer Text die
// Query nicht enthaelt (case-insensitive). Reset bei Leeren des Felds.
// Pure Client-side, keine Server-Round-Trips, keine Persistierung.
//
// Markup-Konvention (Beispiel aus einem List-Blade-Card):
//
//   <div data-controller="list-search"
//        data-list-search-selector-value="li">
//     <input type="text" data-list-search-target="input"
//            data-action="input->list-search#filter"
//            placeholder="Suchen …">
//     <ul>
//       <li>Eintrag A</li>
//       <li>Eintrag B</li>
//     </ul>
//     <p data-list-search-target="empty" class="hidden">Keine Treffer.</p>
//   </div>
//
// `selector` ist optional (default `li`). `empty` ist optional;
// wird angezeigt, wenn die Filterung alle Rows versteckt.
export default class extends Controller {
  static targets = ["input", "empty", "count"]
  static values  = { selector: { type: String, default: "li" }, debounce: { type: Number, default: 120 } }

  connect() {
    this._timer = null
    // #484 (Hans, 2026-06-03): initialen „angezeigt"-Zaehler setzen.
    if (this.hasCountTarget) this._updateCount()
  }

  disconnect() {
    if (this._timer) clearTimeout(this._timer)
  }

  filter() {
    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => this._apply(), this.debounceValue)
  }

  _apply() {
    const q = (this.inputTarget.value || "").trim().toLowerCase()

    // #333 (Hans, 2026-05-24): Disclosure-Gruppen waehrend der Suche
    // expanden, damit auch in collapsed Gruppen Treffer sichtbar sind.
    // Snapshot des Initial-Zustands beim ERSTEN nicht-leeren Input;
    // beim Zuruecksetzen aufs leere Feld wieder herstellen.
    if (q && !this._disclosureSnapshot) {
      this._disclosureSnapshot = this._snapshotDisclosures()
      this._expandAll()
    } else if (!q && this._disclosureSnapshot) {
      this._restoreDisclosures(this._disclosureSnapshot)
      this._disclosureSnapshot = null
    }

    const rows = this.element.querySelectorAll(this.selectorValue)
    let visible = 0
    rows.forEach(row => {
      if (!q) {
        row.classList.remove("list-search-hidden")
        if (!row.classList.contains("hidden")) visible++   // #599
      } else {
        const txt = (row.textContent || "").toLowerCase()
        const match = txt.includes(q)
        row.classList.toggle("list-search-hidden", !match)
        // #599: Zeilen, die ein anderer Filter (content-filter) versteckt,
        // zaehlen nicht als angezeigt.
        if (match && !row.classList.contains("hidden")) {
          visible++
          // Bei einem Klick auf eine Trefferzeile soll der erweiterte
          // Zustand der Disclosures bestehen bleiben (Hans-Spec): wir
          // verwerfen den Snapshot.
          if (!row.dataset.listSearchClickBound) {
            row.dataset.listSearchClickBound = "1"
            row.addEventListener("click", () => { this._disclosureSnapshot = null })
          }
        }
      }
    })
    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visible > 0 || !q)
    }
    // #484 (Hans, 2026-06-03): „angezeigt"-Zaehler live aktualisieren.
    if (this.hasCountTarget) this.countTarget.textContent = visible
  }

  // Sichtbare (nicht via Suche ausgeblendete) Rows zaehlen.
  _updateCount() {
    const rows = this.element.querySelectorAll(this.selectorValue)
    let visible = 0
    rows.forEach(r => {
      if (!r.classList.contains("list-search-hidden") && !r.classList.contains("hidden")) visible++
    })
    this.countTarget.textContent = visible
  }

  _snapshotDisclosures() {
    return Array.from(this.element.querySelectorAll('[data-controller~="disclosure"]'))
      .map(el => ({ el, collapsed: el.dataset.collapsed === "true" }))
  }

  _expandAll() {
    if (!this._disclosureSnapshot) return
    this._disclosureSnapshot.forEach(({ el }) => {
      const ctrl = this.application.getControllerForElementAndIdentifier(el, "disclosure")
      if (ctrl && typeof ctrl.expand === "function") ctrl.expand()
    })
  }

  _restoreDisclosures(snapshot) {
    snapshot.forEach(({ el, collapsed }) => {
      const ctrl = this.application.getControllerForElementAndIdentifier(el, "disclosure")
      if (!ctrl) return
      if (collapsed && typeof ctrl.collapseIfOpen === "function") ctrl.collapseIfOpen()
      else if (!collapsed && typeof ctrl.expand === "function") ctrl.expand()
    })
  }
}
