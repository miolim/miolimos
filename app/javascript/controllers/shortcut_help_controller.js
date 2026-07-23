import { Controller } from "@hotwired/stimulus"

// #759 (Hans, 2026-06-23): Tastatur-Shortcut-Übersicht. Global über das
// Topbar-Icon (Lucide keyboard) UND die Taste „?" erreichbar. Das Modal lebt
// hier; der Blade-Stack (`?`-Taste, blade_stack_keyboard#openShortcutHelp)
// dispatcht ein window-Event "shortcut-help:open", das wir abfangen — so
// funktioniert der Trigger auch außerhalb des Blade-Stack-Scopes (Topbar).
//
// Alle bislang vergebenen Shortcuts. Format (Hans): Pluszeichen mit Leerzeichen
// davor/dahinter; Tasten-Spalte umbruchfrei (whitespace-nowrap), Modal breit.
// #1115: Beschreibungen kommen aus der Sprachdatei (js.shortcut_help.*).
const SHORTCUTS = [
  ["Cmd/Ctrl + K", "shortcut_help.search"],
  ["Cmd/Ctrl + .", "shortcut_help.inspector"],
  ["Cmd/Ctrl + E", "shortcut_help.edit_toggle"],
  ["Cmd/Ctrl + S", "shortcut_help.save_stay"],
  ["Cmd/Ctrl + Enter", "shortcut_help.save_preview"],
  ["Cmd/Ctrl + Shift + Enter", "shortcut_help.publish"],
  ["Esc", "shortcut_help.esc_edit"],
  ["Cmd/Ctrl + Alt + ← / →", "shortcut_help.focus_move"],
  ["Cmd/Ctrl + Shift + ← / →", "shortcut_help.card_move"],
  ["Cmd/Ctrl + Alt + ↑", "shortcut_help.expand_or_close"],
  ["Cmd/Ctrl + Alt + ↓", "shortcut_help.collapse"],
  ["Alt + ← / →", "shortcut_help.trail"],
  ["Alt + C", "shortcut_help.close_active"],
  ["g  c", "shortcut_help.close_focused"],
  ["g  d", "shortcut_help.task_done"],
  ["Tab / Shift + Tab", "shortcut_help.indent"],
  ["?", "shortcut_help.this_help"],
]

export default class extends Controller {
  connect() {
    this._onWindowOpen = () => this.open()
    window.addEventListener("shortcut-help:open", this._onWindowOpen)
  }

  disconnect() {
    window.removeEventListener("shortcut-help:open", this._onWindowOpen)
  }

  open() {
    if (document.getElementById("shortcut_help_modal")) return

    const rows = SHORTCUTS.map(([key, descKey]) =>
      `<tr>
         <td class="py-1.5 pr-8 font-mono text-xs text-slate-700 whitespace-nowrap">${key}</td>
         <td class="py-1.5 text-slate-600">${window.t(descKey)}</td>
       </tr>`
    ).join("")

    const overlay = document.createElement("div")
    overlay.id = "shortcut_help_modal"
    overlay.className = "fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4"
    overlay.innerHTML = `
      <div class="bg-white rounded-lg shadow-xl max-w-2xl w-full p-5 space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="font-semibold">${window.t("shortcut_help.title")}</h2>
          <button type="button" data-close class="text-slate-500 hover:text-slate-900 text-xl leading-none cursor-pointer">×</button>
        </div>
        <table class="w-full text-sm">
          <tbody class="divide-y divide-slate-100">${rows}</tbody>
        </table>
      </div>`

    const remove = () => {
      overlay.remove()
      document.removeEventListener("keydown", onEsc, true)
    }
    const onEsc = (e) => {
      if (e.key === "Escape") { e.preventDefault(); remove() }
    }
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay || e.target.dataset.close === "") remove()
    })
    document.addEventListener("keydown", onEsc, true)
    document.body.appendChild(overlay)
  }
}
