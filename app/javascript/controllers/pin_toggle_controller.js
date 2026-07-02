import { Controller } from "@hotwired/stimulus"

// #191: 📌-Toggle in der KI-Toolbar. Klick togglet den Pin und
// aktualisiert das Icon ohne Page-Reload.
//
// Markup:
//   <button data-controller="pin-toggle"
//           data-pin-toggle-uuid-value="<uuid>"
//           data-pin-toggle-pinned-value="true|false"
//           data-action="click->pin-toggle#toggle">
//     <svg ...>
//   </button>
export default class extends Controller {
  static values = {
    uuid:   String,
    pinned: Boolean
  }

  async toggle(event) {
    event.preventDefault()
    if (this.busy) return
    this.busy = true
    this.element.style.opacity = "0.5"

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const res = await fetch(`/knowledge_items/${this.uuidValue}/toggle_pin`, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
          ...(csrf ? { "X-CSRF-Token": csrf } : {})
        }
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      this.pinnedValue = !!data.pinned
      this.applyState()
      this.flashToast(data.pinned ? window.t("pin.pinned") : window.t("pin.unpinned"))
    } catch (e) {
      this.flashToast(window.t("pin.error", { message: e.message }))
    } finally {
      this.element.style.opacity = ""
      this.busy = false
    }
  }

  // Wechselt zwischen „leer" und „gefüllt" — visuell über Fill-Klasse
  // auf dem SVG (fill-current vs. fill-none). Plus Farbe.
  applyState() {
    const svg = this.element.querySelector("svg")
    if (svg) {
      if (this.pinnedValue) {
        svg.classList.add("fill-current")
        this.element.classList.add("text-amber-600")
        this.element.classList.remove("text-slate-500")
        this.element.title = window.t("pin.title_unpin")
      } else {
        svg.classList.remove("fill-current")
        this.element.classList.remove("text-amber-600")
        this.element.classList.add("text-slate-500")
        this.element.title = window.t("pin.title_pin")
      }
    }
  }

  flashToast(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    div.innerHTML = `<span class="flex-1 min-w-0">${message}</span>`
    stack.appendChild(div)
    setTimeout(() => div.remove(), 3000)
  }
}
