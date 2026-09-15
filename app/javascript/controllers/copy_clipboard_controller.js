import { Controller } from "@hotwired/stimulus"

// Kopiert ein definiertes Text-Snippet (entweder im content-Target
// oder im content-Value) in die Zwischenablage und zeigt einen Toast.
//
// Markup:
//   <button data-controller="copy-clipboard"
//           data-action="click->copy-clipboard#copy"
//           data-copy-clipboard-content-value="Hello world"
//           data-copy-clipboard-toast-value="Kopiert.">📋</button>
//
// #1617: Optional ein zweiter Text für Umschalt+Klick (Card-Spine: Klick =
// Link, Umschalt+Klick = Wikilink):
//           data-copy-clipboard-wikilink-value="[[#123]]"
//           data-copy-clipboard-wikilink-toast-value="Wikilink kopiert"
// Ohne diesen Wert kopiert auch Umschalt+Klick den normalen Text.
export default class extends Controller {
  static targets = ["content"]
  static values  = {
    content:       String,
    toast:         { type: String, default: "" },
    wikilink:      { type: String, default: "" },
    wikilinkToast: { type: String, default: "" }
  }

  async copy(event) {
    event.preventDefault()
    const wiki = event.shiftKey && this.wikilinkValue
    const text = wiki
      ? this.wikilinkValue
      : (this.hasContentTarget ? this.contentTarget.textContent : this.contentValue)
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
      this.flashToast((wiki ? this.wikilinkToastValue : this.toastValue) || window.t("copy.copied"))
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
    // Als Text, nicht als HTML: der Toast zeigt kopierte Inhalte (z. B. einen
    // KI-Titel), und die sollen nie als Markup gelesen werden.
    const span = document.createElement("span")
    span.className = "flex-1 min-w-0"
    span.textContent = message
    const close = document.createElement("button")
    close.type = "button"
    close.setAttribute("data-action", "click->toast#dismiss")
    close.className = "text-slate-400 hover:text-white text-lg leading-none"
    close.textContent = "×"
    div.append(span, close)
    stack.appendChild(div)
  }
}
