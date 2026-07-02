import { Controller } from "@hotwired/stimulus"

// #301: Quick-Create-Leiste in der Topbar. Icon-Reihe (Aufgabe,
// Wartepunkt, KI, Person); Klick auf ein Icon klappt den zugehoerigen
// Eingabeslot als Popover unter der Topbar auf. Erneuter Klick oder
// Klick ausserhalb schliesst. Nach erfolgreichem Submit (turbo:submit-
// end) schliesst der Slot ebenfalls.
//
// Markup:
//   <div data-controller="quick-create">
//     <button data-action="quick-create#toggle" data-quick-create-slot-param="task">…</button>
//     …
//     <div data-quick-create-target="slot" data-slot="task" class="hidden …">…form…</div>
//   </div>
export default class extends Controller {
  static targets = ["slot"]

  connect() {
    this._outside = (e) => {
      if (!this.element.contains(e.target)) this.closeAll()
    }
    document.addEventListener("click", this._outside)
    // Nach erfolgreichem Submit eines Slot-Forms: Form-Felder leeren
    // (#318: sonst sieht der User beim naechsten Oeffnen den alten
    // Text) und Slot schliessen.
    this._onSubmitEnd = (e) => {
      if (this.element.contains(e.target) && e.detail?.success) {
        if (e.target.tagName === "FORM") this._resetForm(e.target)
        this.closeAll()
      }
    }
    document.addEventListener("turbo:submit-end", this._onSubmitEnd)
    // Esc schliesst den offenen Slot.
    this._onKey = (e) => { if (e.key === "Escape") this.closeAll() }
    document.addEventListener("keydown", this._onKey)

    // #301: g-Praefix-Shortcuts. `g` (ausserhalb Textfeld) scharfschaltet
    // fuer 1.2s; die naechste Taste t/w/k/p oeffnet den passenden Slot.
    // Praefix-Sequenz statt Modifier-Combo — STRG+ALT+T waere unter
    // Linux vom System abgefangen worden.
    this._gArmed = false
    this._gTimer = null
    this._onGKey = (e) => {
      const t = e.target
      const inText = /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName) || t.isContentEditable
      if (inText) return
      if (e.key === "g" && !e.ctrlKey && !e.metaKey && !e.altKey) {
        this._gArmed = true
        clearTimeout(this._gTimer)
        this._gTimer = setTimeout(() => { this._gArmed = false }, 1200)
        return
      }
      if (this._gArmed) {
        this._gArmed = false
        clearTimeout(this._gTimer)
        const slot = { t: "task", w: "awaiting", k: "ki", p: "person", i: "inbox" }[e.key]
        if (slot) { e.preventDefault(); this.openSlot(slot) }
      }
    }
    document.addEventListener("keydown", this._onGKey)
  }

  disconnect() {
    document.removeEventListener("click", this._outside)
    document.removeEventListener("turbo:submit-end", this._onSubmitEnd)
    document.removeEventListener("keydown", this._onKey)
    document.removeEventListener("keydown", this._onGKey)
    clearTimeout(this._gTimer)
  }

  toggle(event) {
    event.preventDefault()
    const which  = event.params.slot
    const slot   = this.slotTargets.find(s => s.dataset.slot === which)
    const isOpen = slot && !slot.classList.contains("hidden")
    this.closeAll()
    if (slot && !isOpen) {
      slot.classList.remove("hidden")
      requestAnimationFrame(() => {
        const input = slot.querySelector("input[type=text], textarea")
        input?.focus()
      })
    }
  }

  // #301: per Shortcut (g-Praefix) direkt einen Slot oeffnen.
  openSlot(which) {
    const slot = this.slotTargets.find(s => s.dataset.slot === which)
    if (!slot) return
    this.closeAll()
    slot.classList.remove("hidden")
    requestAnimationFrame(() => {
      const input = slot.querySelector("input[type=text], textarea")
      input?.focus()
    })
  }

  closeAll() {
    this.slotTargets.forEach(s => s.classList.add("hidden"))
  }

  // #318 (Hans): nach erfolgreichem Submit das Form leeren.
  // form.reset() setzt auf die Default-Values zurueck (= leer), klappt
  // sowohl fuer text-inputs als auch fuer hidden-fields (z.B. die
  // capture-description-Variante). Den Picker-State (Item-Type-Select)
  // explizit auf den ersten Wert zurueck, sonst bleibt z.B. „comment"
  // aus einem KI-Template-Pick stehen.
  _resetForm(form) {
    form.reset()
    form.querySelectorAll("select").forEach(s => { s.selectedIndex = 0 })
  }
}
