import { Controller } from "@hotwired/stimulus"

// #759 (Hans, 2026-06-23): Tastatur-Shortcut-Übersicht. Global über das
// Topbar-Icon (Lucide keyboard) UND die Taste „?" erreichbar. Das Modal lebt
// hier; der Blade-Stack (`?`-Taste, blade_stack_keyboard#openShortcutHelp)
// dispatcht ein window-Event "shortcut-help:open", das wir abfangen — so
// funktioniert der Trigger auch außerhalb des Blade-Stack-Scopes (Topbar).
//
// Format (Hans): Pluszeichen mit Leerzeichen davor/dahinter; Tasten-Spalte
// umbruchfrei (whitespace-nowrap), Modal breit.
// #1115: Beschreibungen kommen aus der Sprachdatei (js.shortcut_help.*).
//
// #1576 (Hans): „Es gibt eine Liste mit Shortcuts. Diese bitte ggf. sortieren
// durch Zwischenüberschriften gliedern. Außerdem die Mausklick-Modifier mit
// aufnehmen." Deshalb Gruppen mit Überschrift. Tasten-Spalte: ein String ist
// eine reine Tastenfolge (sprachneutral), `{ t: "…" }` eine Beschriftung aus
// der Sprachdatei — Mausgesten enthalten Wörter wie „Klick".
//
// Die Maus-Einträge beschreiben, was der Code tut; wer dort etwas ändert, zieht
// die Zeile hier nach:
//   Einträge öffnen   lib/blade_open_menu#oeffnungsart (#1642 — Umschalt zeigt
//                     das Menü, Alt ist kein Modifier mehr); genutzt von
//                     blade_link_controller#append, blade_stack_openers#openFromList
//                     und #openDocument; Seitenleiste nur mit Modifier (nurModifier)
//   Spine             blade_stack_controller#focusCard / #toggleCollapse /
//                     #spineContextMenu
//   Breitengriff      lib/blade_stack_resize (#1152 Übernehmen, #1154 Umkehren)
//   Mausrad           lib/blade_stack_scroll#_handleWheel
//   Rechtsklick Text  paragraph_actions_controller (Vorschau),
//                     cm6_editor_controller#openHighlightMenu (Bearbeiten)
const GROUPS = [
  { title: "shortcut_help.group_general", rows: [
    ["Cmd/Ctrl + K", "shortcut_help.search"],
    ["Cmd/Ctrl + .", "shortcut_help.inspector"],
    ["?", "shortcut_help.this_help"],
  ] },
  { title: "shortcut_help.group_edit", rows: [
    ["Cmd/Ctrl + E", "shortcut_help.edit_toggle"],
    ["Cmd/Ctrl + S", "shortcut_help.save_stay"],
    ["Cmd/Ctrl + Enter", "shortcut_help.save_preview"],
    ["Cmd/Ctrl + Shift + Enter", "shortcut_help.publish"],
    ["Esc", "shortcut_help.esc_edit"],
    ["Tab / Shift + Tab", "shortcut_help.indent"],
  ] },
  { title: "shortcut_help.group_cards", rows: [
    ["Cmd/Ctrl + Alt + ← / →", "shortcut_help.focus_move"],
    ["Cmd/Ctrl + Shift + ← / →", "shortcut_help.card_move"],
    ["Cmd/Ctrl + Alt + ↑", "shortcut_help.expand_or_close"],
    ["Cmd/Ctrl + Alt + ↓", "shortcut_help.collapse"],
    ["Alt + C", "shortcut_help.close_active"],
    ["g  c", "shortcut_help.close_focused"],
    ["Alt + ← / →", "shortcut_help.trail"],
    ["g  d", "shortcut_help.task_done"],
  ] },
  { title: "shortcut_help.group_open", note: "shortcut_help.group_open_note", rows: [
    [{ t: "shortcut_help.key_click" }, "shortcut_help.click_replace"],
    [{ t: "shortcut_help.key_shift_click" }, "shortcut_help.click_menu"],
    [{ t: "shortcut_help.key_mod_click" }, "shortcut_help.click_browser"],
  ] },
  { title: "shortcut_help.group_mouse", rows: [
    [{ t: "shortcut_help.key_spine_click" }, "shortcut_help.spine_click"],
    [{ t: "shortcut_help.key_spine_dblclick" }, "shortcut_help.spine_dblclick"],
    [{ t: "shortcut_help.key_spine_right" }, "shortcut_help.spine_right"],
    [{ t: "shortcut_help.key_resize_dblclick" }, "shortcut_help.resize_dblclick"],
    [{ t: "shortcut_help.key_resize_mod_dblclick" }, "shortcut_help.resize_adopt"],
    [{ t: "shortcut_help.key_resize_mod_drag" }, "shortcut_help.resize_invert"],
    [{ t: "shortcut_help.key_shift_wheel" }, "shortcut_help.wheel"],
    [{ t: "shortcut_help.key_paragraph_right" }, "shortcut_help.paragraph_menu"],
    [{ t: "shortcut_help.key_editor_right" }, "shortcut_help.editor_menu"],
  ] },
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

    const label = (key) => typeof key === "string" ? key : window.t(key.t)
    const sections = GROUPS.map(group => {
      const rows = group.rows.map(([key, descKey]) =>
        `<tr>
           <td class="py-1.5 pr-8 font-mono text-xs text-slate-700 whitespace-nowrap align-top">${label(key)}</td>
           <td class="py-1.5 text-slate-600">${window.t(descKey)}</td>
         </tr>`
      ).join("")
      const note = group.note
        ? `<p class="text-xs text-slate-500">${window.t(group.note)}</p>`
        : ""
      return `
        <section class="space-y-1">
          <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-500">${window.t(group.title)}</h3>
          ${note}
          <table class="w-full text-sm">
            <tbody class="divide-y divide-slate-100">${rows}</tbody>
          </table>
        </section>`
    }).join("")

    const overlay = document.createElement("div")
    overlay.id = "shortcut_help_modal"
    overlay.className = "fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4"
    overlay.innerHTML = `
      <div class="bg-white rounded-lg shadow-xl max-w-3xl w-full max-h-[90vh] overflow-y-auto p-5 space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="font-semibold">${window.t("shortcut_help.title")}</h2>
          <button type="button" data-close class="text-slate-500 hover:text-slate-900 text-xl leading-none cursor-pointer">×</button>
        </div>
        ${sections}
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
