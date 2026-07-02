import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-and-Drop-Sortierung für Task-Listen. Nutzt Sortable.js, das
// Touch + Maus nativ unterstützt — HTML5-Drag funktioniert auf
// Mobile zu unzuverlässig.
//
// Markup:
//   <ol data-controller="sortable"
//       data-sortable-reorder-url-value="/topics/<slug>/reorder_tasks">
//     <li data-task-id="42" class="...">
//       <span class="sortable-handle">⋮⋮</span>
//       …
//     </li>
//   </ol>
//
// Optionen:
//   - filter: ".not-draggable"  → erledigte Zeilen kriegen diese Klasse
//   - handle: ".sortable-handle" → nur der Grip startet den Drag
//   - ghostClass / chosenClass / dragClass → visuelle Zustände
export default class extends Controller {
  static values = { reorderUrl: String, group: String }

  connect() {
    // #234: keine eigene .sortable-handle mehr — die ganze Row ist
    // Drag-Handle. Desktop: cursor:grab-Hover-Hint (siehe tasks/_row.html.erb),
    // kleine Bewegungen bleiben Klicks dank touchStartThreshold/
    // fallbackTolerance. Mobile: 300ms-Long-Press startet den Drag
    // (delayOnTouchOnly), kurzer Tap oeffnet weiterhin den Blade-Klick.
    const options = {
      filter:      ".not-draggable",
      draggable:   "[data-task-id]",
      animation:   150,
      ghostClass:  "opacity-40",
      chosenClass: "bg-slate-50",
      dragClass:   "cursor-grabbing",
      forceFallback:          true,   // einheitliches Verhalten auf Touch + Maus
      fallbackTolerance:      5,
      touchStartThreshold:    5,
      delay:                  300,    // 300ms Long-Press auf Touch — kein Mini-Tap = Drag
      delayOnTouchOnly:       true,

      onUpdate: (evt) => this.onEnd(evt),   // interne Umsortierung
      onAdd:    (evt) => this.onEnd(evt)    // aus anderer Gruppe hinzugekommen
    }
    // Nur wenn es einen Group-Value gibt (Verbindung zum Slot), wird er
    // gesetzt — sonst ist die Liste isoliert (Default-Verhalten).
    if (this.hasGroupValue && this.groupValue) {
      options.group = { name: this.groupValue, pull: true, put: true }
    }
    this.sortable = Sortable.create(this.element, options)

    // #234 follow-up: auf Brave/Chrome-Android poppt beim 300ms-Long-Press
    // das Browser-Kontextmenü („Link in neuem Tab öffnen", „Adresse
    // kopieren") auf, bevor SortableJS den Drag starten kann. Wir
    // suppressen contextmenu nur dann, wenn die letzte Pointer-Interaktion
    // ein Touch/Pen war — Desktop-Rechtsklick auf einen Link bleibt damit
    // unangetastet.
    this._lastPointerWasTouch = false
    this._pointerHandler = (e) => {
      this._lastPointerWasTouch = e.pointerType === "touch" || e.pointerType === "pen"
    }
    this._contextMenuHandler = (e) => {
      if (this._lastPointerWasTouch) e.preventDefault()
    }
    this.element.addEventListener("pointerdown", this._pointerHandler, true)
    this.element.addEventListener("contextmenu", this._contextMenuHandler)
  }

  disconnect() {
    this.sortable?.destroy()
    if (this._pointerHandler) this.element.removeEventListener("pointerdown", this._pointerHandler, true)
    if (this._contextMenuHandler) this.element.removeEventListener("contextmenu", this._contextMenuHandler)
  }

  onEnd(_evt) {
    if (!this.reorderUrlValue) return
    const ids = Array.from(this.element.querySelectorAll("[data-task-id]"))
      .map(el => el.dataset.taskId)

    const showDone = new URLSearchParams(window.location.search).get("show_done")
    const body = new URLSearchParams()
    body.set("ordered_task_ids", ids.join(","))
    if (showDone) body.set("show_done", showDone)

    fetch(this.reorderUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: body.toString()
    }).then(async (res) => {
      if (!res.ok) { console.warn("reorder failed:", res.status); location.reload(); return }
      const html = await res.text()
      if (html && html.trim()) window.Turbo.renderStreamMessage(html)
    }).catch((err) => {
      console.warn("reorder error:", err)
      location.reload()
    })
  }
}
