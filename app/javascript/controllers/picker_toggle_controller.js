import { Controller } from "@hotwired/stimulus"

// Minimaler Trigger-Klick-Toggle fuer Picker, die nicht zum
// entity-picker-Pattern passen (z.B. Quelle: text_field mit Slug-
// Autocomplete via source-picker statt Chips). Zeigt im Default einen
// klickbaren Label-Trigger; beim Klick erscheint das umschliessende
// inputBox + es wird das erste Input fokussiert. Blur mit leerem Input
// faellt zurueck. #389 (Hans, 2026-05-28).
export default class extends Controller {
  static targets = ["trigger", "inputBox"]

  // #603 R4 (Hans): die GANZE Zeile ist klickbar — Klicks auf
  // interaktive Elemente (Chips, Formulare, Links) bleiben unberührt.
  openFromRow(event) {
    if (event.target.closest("a, button, input, select, textarea, label, form")) return
    this.open(event)
  }

  open(event) {
    event?.preventDefault()
    if (!this.hasTriggerTarget || !this.hasInputBoxTarget) return
    const isOpen = !this.inputBoxTarget.hidden
    if (isOpen) {
      this.close()
      return
    }
    this.triggerTarget.hidden  = true
    this.inputBoxTarget.hidden = false
    // #603 R5: solange das Eingabefeld offen ist, Hover-Effekte der
    // Zeile abschalten (sonst springt es beim Mausbewegen).
    this.element.classList.add("erow-open")
    const input = this.inputBoxTarget.querySelector("input, textarea, select")
    // Browser unterdrueckt focus() auf gerade-aus-hidden-genommene
    // Elemente in einigen Fenstern; ein extra rAF stellt sicher,
    // dass der Layout-Pass durch ist, bevor wir den Cursor setzen.
    // Hans-Spec (2026-05-28): Cursor MUSS bei Quelle direkt im Feld
    // sitzen.
    if (input) {
      requestAnimationFrame(() => {
        input.focus()
        // #603 R5: Datumsfelder öffnen sofort den nativen Picker.
        if (input.type === "date") { try { input.showPicker?.() } catch (_) {} }
        // Cursor ans Ende (falls schon ein Wert drin steht).
        const v = input.value
        if (v) {
          input.setSelectionRange?.(v.length, v.length)
        }
      })
    }
    if (input && !this._blurAttached) {
      this._blurAttached = true
      input.addEventListener("blur", () => {
        setTimeout(() => {
          if (document.activeElement === input) return
          if (input.value) return
          this.close()
        }, 180)
      })
    }
  }

  close() {
    if (!this.hasTriggerTarget || !this.hasInputBoxTarget) return
    this.triggerTarget.hidden  = false
    this.inputBoxTarget.hidden = true
    this.element.classList.remove("erow-open")
  }
}
