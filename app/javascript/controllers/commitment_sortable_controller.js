import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-and-Drop zwischen den vier My-Tasks-Sektionen (Eingang / Heute /
// Demnächst / Später). Alle vier Sektionen teilen sich eine Sortable-
// Gruppe "commitment", sodass Tasks zwischen ihnen gezogen werden können.
//
// Beim Drop in eine andere Sektion (onAdd) wird POST /tasks/:id/set_commitment
// gefeuert — der Server antwortet mit Turbo-Streams, die die Row und ggf.
// die Empty-State-Hinweise aktualisieren.
export default class extends Controller {
  static values = { commitment: String }

  connect() {
    // #234: keine eigene .sortable-handle mehr — die ganze Row ist
    // Drag-Handle. Mobile: 300ms Long-Press, Desktop: kleine Bewegungen
    // bleiben Klicks dank touchStartThreshold/fallbackTolerance.
    this.sortable = Sortable.create(this.element, {
      group:       { name: "commitment", pull: true, put: true },
      filter:      ".not-draggable",
      draggable:   "[data-task-id]",
      animation:   150,
      ghostClass:  "opacity-40",
      chosenClass: "bg-slate-50",
      dragClass:   "cursor-grabbing",
      forceFallback:       true,
      fallbackTolerance:   5,
      touchStartThreshold: 5,
      delay:               300,
      delayOnTouchOnly:    true,

      onAdd: (evt) => this.onCommit(evt)
    })

    // #234 follow-up: Brave/Android-Kontextmenü-Suppression beim Touch-
    // Long-Press, identisch zum sortable_controller.
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

  onCommit(evt) {
    const taskId    = evt.item.dataset.taskId
    const targetVal = this.commitmentValue   // "inbox" | "today" | "soon" | "later"
    if (!taskId) return

    const body = new URLSearchParams()
    body.set("commitment", targetVal)

    fetch(`/tasks/${taskId}/set_commitment`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: body.toString()
    }).then(async (res) => {
      if (!res.ok) { console.warn("set_commitment failed:", res.status); location.reload(); return }
      const html = await res.text()
      if (html && html.trim()) window.Turbo.renderStreamMessage(html)
    }).catch((err) => {
      console.warn("set_commitment error:", err)
      location.reload()
    })
  }
}
