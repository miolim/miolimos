import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag-and-Drop für die Topic-View der Aufgabenliste. Cross-bucket
// drag ändert das Topic des verschobenen Tasks via zwei API-Calls:
//   - DELETE /tasks/:id/topics/:source_slug   (falls Source ≠ "Ohne Projekt")
//   - POST   /tasks/:id/topics?topic_id=:to_slug (falls Target ≠ "Ohne Projekt")
//
// Werte:
//   data-topic-sortable-topic-id-value   — DB-ID des Topics oder leer (Ohne Projekt)
//   data-topic-sortable-topic-slug-value — Slug des Topics oder leer
//
// Reine Sortierung *innerhalb* eines Buckets aktualisiert keine
// serverseitige Position — das gibt's nur in der Wann-View. Hier
// ist die Sortierung gemischt aus Wann + Priorität (Read-only-Reihenfolge).
export default class extends Controller {
  static values = {
    topicId:   String,
    topicSlug: String
  }

  connect() {
    this.sortable = Sortable.create(this.element, {
      group:       { name: "topic", pull: true, put: true },
      handle:      ".sortable-handle",
      filter:      ".not-draggable",
      draggable:   "[data-task-id]",
      animation:   150,
      ghostClass:  "opacity-40",
      chosenClass: "bg-slate-50",
      dragClass:   "cursor-grabbing",
      forceFallback:    true,
      fallbackTolerance: 5,
      delay:            100,
      delayOnTouchOnly: true,

      onAdd: (evt) => this.onTopicChange(evt)
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  async onTopicChange(evt) {
    const taskId = evt.item.dataset.taskId
    if (!taskId) return

    const fromCtrl = this.application.getControllerForElementAndIdentifier(evt.from, "topic-sortable")
    const fromSlug = fromCtrl?.topicSlugValue || ""
    const toSlug   = this.topicSlugValue       || ""
    if (fromSlug === toSlug) return  // gleiches Topic — no-op

    const csrf = document.querySelector("meta[name='csrf-token']")?.content

    try {
      // 1) Quelle entfernen (außer wir kommen aus „Ohne Projekt")
      if (fromSlug) {
        const delRes = await fetch(`/tasks/${taskId}/topics/${fromSlug}`, {
          method: "DELETE",
          headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": csrf }
        })
        if (!delRes.ok) throw new Error(`DELETE failed: ${delRes.status}`)
      }
      // 2) Ziel hinzufügen (außer wir landen in „Ohne Projekt")
      if (toSlug) {
        const body = new URLSearchParams()
        body.set("topic_id", toSlug)
        const addRes = await fetch(`/tasks/${taskId}/topics`, {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "text/vnd.turbo-stream.html",
            "X-CSRF-Token": csrf
          },
          body: body.toString()
        })
        if (!addRes.ok) throw new Error(`POST failed: ${addRes.status}`)
      }
    } catch (e) {
      console.warn("topic move failed:", e)
      location.reload()
    }
  }
}
