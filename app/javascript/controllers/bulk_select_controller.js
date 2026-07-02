import { Controller } from "@hotwired/stimulus"

// Bulk-Auswahl-Modus fuer Aufgaben-Listen. #388.
//
// Erwartete DOM-Struktur:
//   <div data-controller="bulk-select">
//     <button data-action="bulk-select#toggleMode">…</button>
//     <ul ...>
//       <li class="bulk-row">
//         <input type="checkbox" data-bulk-select-target="checkbox" data-task-id="42">
//         …rest of row…
//       </li>
//     </ul>
//     <div data-bulk-select-target="bar" hidden>
//       <span data-bulk-select-target="counter">0</span>
//       …form fields…
//       <button data-action="bulk-select#apply">Anwenden</button>
//       <button data-action="bulk-select#cancel">Abbrechen</button>
//     </div>
//   </div>
//
// CSS schaltet Checkbox-Sichtbarkeit ueber `.bulk-active` auf der Wurzel.
export default class extends Controller {
  static targets = ["bar", "checkbox", "counter", "applyForm"]
  static values  = { url: String }

  connect() {
    this.active = false
    this.update()
  }

  toggleMode(event) {
    event?.preventDefault()
    this.active = !this.active
    this.element.classList.toggle("bulk-active", this.active)
    if (!this.active) {
      this.checkboxTargets.forEach(cb => { cb.checked = false })
    }
    this.update()
  }

  toggleRow() {
    this.update()
  }

  cancel(event) {
    event?.preventDefault()
    this.active = false
    this.element.classList.remove("bulk-active")
    this.checkboxTargets.forEach(cb => { cb.checked = false })
    this.update()
  }

  selectedIds() {
    return this.checkboxTargets.filter(cb => cb.checked).map(cb => cb.dataset.taskId)
  }

  update() {
    const ids = this.selectedIds()
    if (this.hasCounterTarget) this.counterTarget.textContent = ids.length
    if (this.hasBarTarget) {
      const show = this.active && ids.length > 0
      this.barTarget.hidden = !show
    }
  }

  // Beim Form-Submit die ausgewaehlten ids[] als hidden inputs anhaengen.
  apply(event) {
    if (!this.hasApplyFormTarget) return
    const form = this.applyFormTarget
    // Alte ids[]-Inputs entfernen (idempotent).
    form.querySelectorAll('input[name="ids[]"]').forEach(el => el.remove())
    this.selectedIds().forEach(id => {
      const input = document.createElement("input")
      input.type  = "hidden"
      input.name  = "ids[]"
      input.value = id
      form.appendChild(input)
    })
  }
}
