import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// #846: Editor fuer das Sidebar-Layout in den Vorlieben. Drei Listen
// (Fest oben / Scrollbereich / Ausgeblendet) teilen sich eine Sortable-
// Gruppe, sodass Eintraege zwischen ihnen gezogen und innerhalb sortiert
// werden koennen. Nach jeder Aenderung werden die drei Hidden-Inputs
// (komma-separierte IDs je Bereich) aktualisiert — die Vorlieben-Form
// schickt sie beim Speichern mit.
//
// #1109: Sections/Namen kommen komplett aus dem Markup (data-section,
// input-name) — derselbe Controller treibt darum auch den Topbar-Layout-
// Editor. Nur die Sortable-Gruppe muss sich unterscheiden (group-Value),
// sonst koennte man Eintraege zwischen den beiden Editoren ziehen.
export default class extends Controller {
  static targets = ["list", "input"]
  static values  = {
    default: Object, labels: Object, icons: Object,
    group:   { type: String, default: "sidebar-layout" },
    // #1612: Texte für freie Überschriften (nur der Sidebar-Editor setzt sie).
    headingName: String, headingLabel: String, headingRemove: String
  }

  connect() {
    // Sortable.js (Touch + Maus), gleiche Optionen wie commitment_sortable:
    // ganze Zeile ist Drag-Handle, 300ms Long-Press auf Touch, kleine
    // Bewegungen bleiben Klicks.
    this.sortables = this.listTargets.map((list) =>
      Sortable.create(list, {
        group:               this.groupValue,
        draggable:           "[data-item-id]",
        animation:           150,
        ghostClass:          "opacity-40",
        chosenClass:         "bg-slate-100",
        dragClass:           "cursor-grabbing",
        forceFallback:       true,
        fallbackTolerance:   5,
        touchStartThreshold: 5,
        delay:               300,
        delayOnTouchOnly:    true,
        // #1612: Ins Namensfeld klicken und das × drücken darf kein Ziehen
        // starten.
        filter:              "input, button",
        preventOnFilter:     false,
        onSort:              () => this.sync()
      })
    )
    this.sync()
  }

  disconnect() {
    this.sortables?.forEach((s) => s.destroy())
  }

  // Alle drei Hidden-Inputs aus dem aktuellen DOM-Zustand neu befuellen.
  sync() {
    this.listTargets.forEach((list) => {
      const section = list.dataset.section
      const ids = Array.from(list.querySelectorAll("[data-item-id]")).map((el) => el.dataset.itemId)
      const input = this.inputTargets.find((i) => i.dataset.section === section)
      if (input) input.value = ids.join(",")
    })
  }

  // Auf das Default-Layout zuruecksetzen (baut die drei Listen neu auf).
  reset(e) {
    e.preventDefault()
    const def    = this.defaultValue   // { pinned: [...], scroll: [...], hidden: [...] }
    const labels = this.labelsValue    // { id: "Label", ... }
    const icons  = this.iconsValue     // { id: "<svg…>", ... }
    this.listTargets.forEach((list) => {
      const section = list.dataset.section
      list.innerHTML = ""
      ;(def[section] || []).forEach((id) => list.appendChild(this.buildItem(id, labels[id] || id, icons[id])))
    })
    this.sync()
  }

  // #1612 (Hans): neue Überschrift — landet oben im Scrollbereich, der Name
  // ist gleich markiert, damit man direkt lostippen kann. Gespeichert wird
  // erst mit dem Formular (Name über das Feld, Platz über die Hidden-Inputs).
  addHeading(e) {
    e.preventDefault()
    const list = this.listTargets.find((l) => l.dataset.section === "scroll") || this.listTargets[0]
    if (!list) return
    const bytes = new Uint8Array(4)
    crypto.getRandomValues(bytes)
    const token = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")
    const li = this.buildHeading(token, this.headingNameValue)
    list.prepend(li)
    this.sync()
    const input = li.querySelector("input")
    input.focus()
    input.select()
  }

  removeHeading(e) {
    e.preventDefault()
    e.currentTarget.closest("[data-item-id]")?.remove()
    this.sync()
  }

  // Gleiches Markup wie im Vorlieben-Partial (settings/blades/_preferences).
  buildHeading(token, name) {
    const li = document.createElement("li")
    li.dataset.itemId = `heading:${token}`
    li.dataset.heading = ""
    li.className = "flex items-center gap-2 px-2 py-1 rounded border border-dashed border-slate-300 bg-slate-100 text-sm cursor-grab select-none"
    const grip = document.createElement("span")
    grip.className = "text-slate-400 shrink-0"
    grip.textContent = "⋮⋮"
    const input = document.createElement("input")
    input.type = "text"
    input.name = `preferences[sidebar_headings][${token}]`
    input.value = name || ""
    input.maxLength = 40
    input.required = true
    input.setAttribute("aria-label", this.headingLabelValue)
    input.className = "flex-1 min-w-0 select-text text-[11px] uppercase tracking-wider bg-transparent border-0 px-0 py-0 focus:outline-none focus:ring-0"
    const remove = document.createElement("button")
    remove.type = "button"
    remove.dataset.action = "sidebar-layout-editor#removeHeading"
    remove.title = this.headingRemoveValue
    remove.setAttribute("aria-label", this.headingRemoveValue)
    remove.className = "shrink-0 text-slate-400 hover:text-rose-600 cursor-pointer bg-transparent border-0 px-1"
    remove.textContent = "×"
    li.append(grip, input, remove)
    return li
  }

  buildItem(id, label, iconSvg) {
    const li = document.createElement("li")
    li.dataset.itemId = id
    li.className = "flex items-center gap-2 px-2 py-1 rounded border border-slate-200 bg-white text-sm cursor-grab select-none"
    const grip = document.createElement("span")
    grip.className = "text-slate-400 shrink-0"
    grip.textContent = "⋮⋮"
    const iconSlot = document.createElement("span")
    iconSlot.className = "w-4 flex items-center justify-center shrink-0 text-slate-500"
    if (iconSvg) iconSlot.innerHTML = iconSvg
    const span = document.createElement("span")
    span.className = "truncate"
    span.textContent = label
    li.append(grip, iconSlot, span)
    return li
  }
}
