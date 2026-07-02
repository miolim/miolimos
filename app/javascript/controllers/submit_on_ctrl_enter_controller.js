import { Controller } from "@hotwired/stimulus"
import { dispatchBladeShortcut } from "lib/submit_shortcuts"

// #279: Ctrl/Cmd+Enter Save-Shortcut. Wird einmal an
// `<body data-controller="submit-on-ctrl-enter">` montiert.
// #451 (Hans, 2026-06-02): Die Shortcuts beziehen sich jetzt auf das
// AKTIVE Blade (Spine markiert) — Logik in lib/submit_shortcuts (geteilt
// mit der CM6-Keymap). Dieser globale Handler deckt Plain-Felder und den
// fokuslosen Fall (z.B. nach einem Entwurf-Save) ab; Events aus dem
// CM6-Editor ueberspringt er, die behandelt die CM6-Keymap selbst.
export default class extends Controller {
  connect() {
    this._handler = (e) => {
      if (!(e.ctrlKey || e.metaKey) || e.key !== "Enter") return
      const el = e.target
      // CM6 behandelt seine eigenen Tastendruecke ueber die Keymap —
      // sonst wuerde die Aktion doppelt feuern.
      if (el?.closest?.(".cm-editor")) return
      const handled = dispatchBladeShortcut({ shiftKey: e.shiftKey, contextEl: el })
      if (handled) e.preventDefault()
    }
    document.addEventListener("keydown", this._handler)
  }

  disconnect() {
    if (this._handler) document.removeEventListener("keydown", this._handler)
  }
}
