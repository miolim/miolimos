import { Controller } from "@hotwired/stimulus"

// #325 (Hans, 2026-05-24): "+ in Work-Tree"-Icon-Klick auf einer
// KI-Liste-Zeile (innerhalb eines Topic-Knowledge-Tabs). POSTet zu
// /topics/:slug/work_nodes mit role=heading; Server antwortet mit
// Turbo-Stream-Replace des Topic-Blades — der Work-Tree-Tab eines
// im Stack offenen zweiten Topic-Blades aktualisiert sich automatisch.
export default class extends Controller {
  static values = { topicSlug: String, kiUuid: String }

  async add(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.topicSlugValue || !this.kiUuidValue) return
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const fd = new FormData()
    fd.append("knowledge_item_uuid", this.kiUuidValue)
    fd.append("role", "heading")
    try {
      const res = await fetch(`/topics/${encodeURIComponent(this.topicSlugValue)}/work_nodes`, {
        method: "POST",
        body: fd,
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrf
        }
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({}))
        alert(window.t("add_to_work_tree.add_failed", { error: err.error || res.status }))
        return
      }
      const html = await res.text()
      if (window.Turbo) window.Turbo.renderStreamMessage(html)
    } catch (err) {
      console.warn("add-to-work-tree: fetch failed", err)
    }
  }
}
