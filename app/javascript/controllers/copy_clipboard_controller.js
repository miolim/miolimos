import { Controller } from "@hotwired/stimulus"

// Kopiert ein definiertes Text-Snippet (entweder im content-Target
// oder im content-Value) in die Zwischenablage und zeigt einen Toast.
//
// Markup:
//   <button data-controller="copy-clipboard"
//           data-action="click->copy-clipboard#copy"
//           data-copy-clipboard-content-value="Hello world"
//           data-copy-clipboard-toast-value="Kopiert.">📋</button>
export default class extends Controller {
  static targets = ["content"]
  static values  = {
    content: String,
    toast:   { type: String, default: "" }
  }

  async copy(event) {
    event.preventDefault()
    const text = this.hasContentTarget
      ? this.contentTarget.textContent
      : this.contentValue
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
      this.flashToast(this.toastValue || window.t("copy.copied"))
    } catch (err) {
      console.warn("clipboard copy failed:", err)
      this.flashToast(window.t("copy.copy_failed"))
    }
  }

  flashToast(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    div.innerHTML = `<span class="flex-1 min-w-0">${message}</span>
      <button type="button" data-action="click->toast#dismiss"
              class="text-slate-400 hover:text-white text-lg leading-none">×</button>`
    stack.appendChild(div)
  }
}
