import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// #846: Editor fuer das Sidebar-Layout in den Vorlieben. Drei Listen
// (Fest oben / Scrollbereich / Ausgeblendet) teilen sich eine Sortable-
// Gruppe, sodass Eintraege zwischen ihnen gezogen und innerhalb sortiert
// werden koennen. Nach jeder Aenderung werden die drei Hidden-Inputs
// (komma-separierte IDs je Bereich) aktualisiert — die Vorlieben-Form
// schickt sie beim Speichern mit.
export default class extends Controller {
  static targets = ["list", "input"]
  static values  = { default: Object, labels: Object, icons: Object }

  connect() {
    // Sortable.js (Touch + Maus), gleiche Optionen wie commitment_sortable:
    // ganze Zeile ist Drag-Handle, 300ms Long-Press auf Touch, kleine
    // Bewegungen bleiben Klicks.
    this.sortables = this.listTargets.map((list) =>
      Sortable.create(list, {
        group:               "sidebar-layout",
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
