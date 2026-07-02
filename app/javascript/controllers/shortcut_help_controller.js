import { Controller } from "@hotwired/stimulus"

// #759 (Hans, 2026-06-23): Tastatur-Shortcut-Übersicht. Global über das
// Topbar-Icon (Lucide keyboard) UND die Taste „?" erreichbar. Das Modal lebt
// hier; der Blade-Stack (`?`-Taste, blade_stack_keyboard#openShortcutHelp)
// dispatcht ein window-Event "shortcut-help:open", das wir abfangen — so
// funktioniert der Trigger auch außerhalb des Blade-Stack-Scopes (Topbar).
//
// Alle bislang vergebenen Shortcuts. Format (Hans): Pluszeichen mit Leerzeichen
// davor/dahinter; Tasten-Spalte umbruchfrei (whitespace-nowrap), Modal breit.
const SHORTCUTS = [
  ["Cmd/Ctrl + K", "Suche fokussieren"],
  ["Cmd/Ctrl + .", "Beschriftungs-Modus an/aus"],
  ["Cmd/Ctrl + E", "Bearbeiten ↔ Vorschau"],
  ["Cmd/Ctrl + S", "Speichern (im Bearbeiten bleiben)"],
  ["Cmd/Ctrl + Enter", "Speichern, zurück zur Vorschau"],
  ["Cmd/Ctrl + Shift + Enter", "Entwurf veröffentlichen"],
  ["Esc", "Bearbeiten verlassen ohne Speichern"],
  ["Cmd/Ctrl + Alt + ← / →", "Card-Fokus im Stack wechseln"],
  ["Cmd/Ctrl + Shift + ← / →", "Aktive Card im Stack verschieben"],
  ["Cmd/Ctrl + Alt + ↑", "Eingeklappt → ausklappen, sonst Card schließen"],
  ["Cmd/Ctrl + Alt + ↓", "Aktive Card einklappen"],
  ["Alt + ← / →", "Verlauf-Schritt zurück / vor"],
  ["Alt + C", "Aktive Card schließen"],
  ["g  c", "Fokussierte Card schließen"],
  ["g  d", "Aufgabe erledigt / nicht erledigt"],
  ["Tab / Shift + Tab", "Zeile ein- / ausrücken (im Textfeld)"],
  ["?", "Diese Hilfe"],
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

    const rows = SHORTCUTS.map(([key, desc]) =>
      `<tr>
         <td class="py-1.5 pr-8 font-mono text-xs text-slate-700 whitespace-nowrap">${key}</td>
         <td class="py-1.5 text-slate-600">${desc}</td>
       </tr>`
    ).join("")

    const overlay = document.createElement("div")
    overlay.id = "shortcut_help_modal"
    overlay.className = "fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4"
    overlay.innerHTML = `
      <div class="bg-white rounded-lg shadow-xl max-w-2xl w-full p-5 space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="font-semibold">Tastatur-Shortcuts</h2>
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
