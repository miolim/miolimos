import { Controller } from "@hotwired/stimulus"

// #155: Bulk-Trigger für Researcher-getriebenen Entity-Import. Zeigt
// sich nur, wenn die KI mindestens einen Wikilink mit Source-URL hat,
// der noch nicht als KI auflöst (= roter Wikilink mit data-source-url).
// Klick legt einen Task assigned an miolim_researcher an.
//
// Markup:
//   <div data-controller="bulk-entity-import"
//        data-bulk-entity-import-uuid-value="<uuid>">
//     <button data-action="click->bulk-entity-import#submit"
//             data-bulk-entity-import-target="button">…</button>
//   </div>
export default class extends Controller {
  static targets = ["button"]
  static values  = { uuid: String }

  connect() {
    // Scope auf das umgebende KI-Wrapper, damit bei Sliding-Pane-Stack
    // mit mehreren KIs jede Bulk-Button-Instanz nur ihre eigene KI
    // betrachtet.
    this.kiRoot = this.element.closest('[id^="knowledge_"]') || document.body
    this.updateVisibility()
    // Re-evaluiere, wenn das Body-Markup live ersetzt wird (Edit-Save
    // bringt ein neues Preview-Partial).
    this.observer = new MutationObserver(() => this.updateVisibility())
    this.observer.observe(this.kiRoot, { childList: true, subtree: true })
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  updateVisibility() {
    const count = this.kiRoot.querySelectorAll('a.wikilink-missing[data-source-url]').length
    if (count > 0) {
      this.element.classList.remove("hidden")
      this.buttonTarget.title = window.t("bulk_import.button_title", { count: count })
      this.buttonTarget.dataset.bulkCount = String(count)
    } else {
      this.element.classList.add("hidden")
    }
  }

  async submit(event) {
    event.preventDefault()
    const button = this.buttonTarget
    button.disabled = true
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const response = await fetch(`/knowledge_items/${this.uuidValue}/request_entity_import`, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
          ...(csrf ? { "X-CSRF-Token": csrf } : {})
        }
      })
      const data = await response.json()
      if (response.ok && data.task_id) {
        this.flashToast(window.t("bulk_import.created", { count: data.count, task_id: data.task_id }))
        this.element.classList.add("hidden")
      } else {
        this.flashToast(data.error || data.message || window.t("bulk_import.request_failed"))
        button.disabled = false
      }
    } catch (e) {
      this.flashToast(window.t("bulk_import.error", { message: e.message }))
      button.disabled = false
    }
  }

  flashToast(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    div.innerHTML = `<span class="flex-1 min-w-0"></span>
      <button type="button" data-action="click->toast#dismiss"
              class="text-slate-400 hover:text-white text-lg leading-none">×</button>`
    div.querySelector("span").textContent = message
    stack.appendChild(div)
  }
}
