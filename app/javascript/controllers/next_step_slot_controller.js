import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drop-Zone für den Next-Step-Slot eines Themas. Teilt sich die Group
// mit der Open-Tasks-Liste, damit Items zwischen den beiden Containern
// gezogen werden können. Touch + Maus identisch (Sortable.js).
//
// Beim Hereinziehen feuert onAdd, wir POSTen set_next_step. Beim
// Hinausziehen feuert onEnd auf uns, aber die Liste hat ein onAdd
// angehakt — die POSTet reorder_tasks, was serverseitig next_step
// wegräumt.
export default class extends Controller {
  static values = { setUrl: String, group: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      handle:     ".sortable-handle",
      filter:     ".not-draggable",
      draggable:  "[data-task-id]",
      animation:  150,
      ghostClass: "opacity-40",
      dragClass:  "cursor-grabbing",
      forceFallback:       true,
      fallbackTolerance:   5,
      delay:               100,
      delayOnTouchOnly:    true,
      group: { name: this.groupValue, pull: true, put: true },

      onAdd: (evt) => this.onAdd(evt)
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  onAdd(evt) {
    const taskId = evt.item.dataset.taskId
    if (!taskId) return

    const showDone = new URLSearchParams(window.location.search).get("show_done")
    const body = new URLSearchParams()
    body.set("task_id", taskId)
    if (showDone) body.set("show_done", showDone)

    fetch(this.setUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: body.toString()
    }).then(async (res) => {
      if (res.ok) {
        const html = await res.text()
        if (html && html.trim()) window.Turbo.renderStreamMessage(html)
      } else {
        console.warn("set_next_step failed:", res.status)
        location.reload()
      }
    }).catch((err) => {
      console.warn("set_next_step error:", err)
      location.reload()
    })
  }
}
