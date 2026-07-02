import { Controller } from "@hotwired/stimulus"

// #183: Per-Wikilink-Recherche-Trigger. Klick auf das 🔍-Icon hinter
// einem roten [[Title|URL]]-Wikilink legt einen Researcher-Task an
// und ersetzt das Icon durch ⏳ mit Link zum Task.
//
// Markup (wird von KnowledgeMarkdown::Wikilinks gerendert):
//   <a data-controller="wikilink-research"
//      data-action="click->wikilink-research#start"
//      data-wikilink-research-source-uuid-value="<uuid>"
//      data-wikilink-research-target-title-value="<title>"
//      data-wikilink-research-target-source-url-value="<url>">🔍</a>
export default class extends Controller {
  static values = {
    sourceUuid:        String,
    targetTitle:       String,
    targetSourceUrl:   String
  }

  async start(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.element.dataset.pending === "true") return
    this.element.dataset.pending = "true"
    this.element.style.opacity = "0.5"

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const res = await fetch(`/knowledge_items/${this.sourceUuidValue}/start_wikilink_research`, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-Requested-With": "XMLHttpRequest",
          ...(csrf ? { "X-CSRF-Token": csrf } : {})
        },
        body: JSON.stringify({
          title: this.targetTitleValue,
          source_url: this.targetSourceUrlValue
        })
      })
      const data = await res.json()
      if (res.ok && data.task_id) {
        this.swapToPending(data.task_id)
        this.flashToast(window.t("research.task_created", { id: data.task_id }))
        // #659 (Hans): den frischen Recherche-Task direkt als Blade an
        // den aktuellen Stack anhängen (gleicher Weg wie blade-link).
        if (document.body.classList.contains("has-blade-stack")) {
          window.dispatchEvent(new CustomEvent("blade-stack:append", {
            detail: { kind: "task", id: String(data.task_id), anchor: null,
                      sourceListId: null, mode: "append_to_substack" }
          }))
        }
      } else {
        this.element.style.opacity = ""
        this.element.dataset.pending = "false"
        this.flashToast(data.error || window.t("research.start_failed"))
      }
    } catch (e) {
      this.element.style.opacity = ""
      this.element.dataset.pending = "false"
      this.flashToast(window.t("research.error", { message: e.message }))
    }
  }

  swapToPending(taskId) {
    const pending = document.createElement("a")
    pending.href = `/tasks/${taskId}`
    pending.className = "wikilink-research-pending text-amber-600 hover:text-amber-700"
    pending.target = "_blank"
    pending.setAttribute("data-turbo-frame", "_top")
    pending.title = window.t("research.pending_title", { id: taskId })
    pending.innerHTML = this.element.innerHTML
    this.element.replaceWith(pending)
  }

  flashToast(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) {
      console.log(message)
      return
    }
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    div.innerHTML = `<span class="flex-1 min-w-0">${message}</span>`
    stack.appendChild(div)
    setTimeout(() => div.remove(), 4000)
  }
}
