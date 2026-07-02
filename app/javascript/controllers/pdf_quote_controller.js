import { Controller } from "@hotwired/stimulus"

// Quote-Knopf in der PDF-Card-Toolbar. Liest den markierten Text aus
// der Zwischenablage und schickt ihn ans `quote_from_clipboard`-
// Endpoint des PDFs. Der Server hängt den Quote in eine "Best-of"-
// Sammlung (`Quotes aus <pdf-title>`) — beim ersten Quote wird die
// Sammlung angelegt, danach jedem weiteren Quote angehängt.
//
// User-Flow: Text im PDF markieren → Cmd/Ctrl+C → 📋 Quote klicken.
export default class extends Controller {
  static values = { url: String }

  async paste() {
    let text
    try {
      text = (await navigator.clipboard.readText()).trim()
    } catch (err) {
      this.toast(window.t("pdf_quote.clipboard_unavailable"))
      return
    }
    if (!text) {
      this.toast(window.t("pdf_quote.clipboard_empty"))
      return
    }

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({ text })
    const res  = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept":       "application/json",
        "X-CSRF-Token": csrf
      },
      body: body.toString()
    })
    if (!res.ok) { this.toast(window.t("pdf_quote.append_failed")); return }
    const data = await res.json()

    // Sammlung im Stack öffnen oder refreshen.
    const stackCtl = this.findBladeStackController()
    if (stackCtl) {
      const existing = stackCtl.cardForUuid(data.uuid)
      if (existing) {
        await stackCtl.refreshCard(data.uuid)
      } else {
        await stackCtl.appendCard(data.uuid)
      }
      stackCtl.restickify?.()
      stackCtl.applyHighlighting?.()
      stackCtl.syncUrl?.({ pushHistory: false })
    }
    this.toast(data.created ? window.t("pdf_quote.collection_created") : window.t("pdf_quote.quote_added"))
  }

  findBladeStackController() {
    const stackEl = document.querySelector("[data-controller~=blade-stack]")
    if (!stackEl) return null
    return window.Stimulus?.getControllerForElementAndIdentifier(stackEl, "blade-stack")
  }

  toast(msg) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-toast-timeout-value", "4000")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-start gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    div.innerHTML = `<div class="flex-1 min-w-0">${msg.replace(/[<>&]/g, c => ({"<":"&lt;",">":"&gt;","&":"&amp;"}[c]))}</div>
      <button type="button" data-action="click->toast#dismiss"
              class="text-slate-400 hover:text-white text-lg leading-none">×</button>`
    stack.appendChild(div)
  }
}
