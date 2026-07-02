import { Controller } from "@hotwired/stimulus"

// #609: Bild aus der Zwischenablage direkt in den Editor pasten.
// Lädt das Bild hoch (POST /knowledge_items/paste_image → legt eine
// Bild-KI an) und fügt `![[Titel]]` an der Cursor-Position ein.
//
// Sitzt auf demselben Wrapper wie cm6-editor (Body-Edit der KI,
// Antwort-Compose) — Paste-Events bubblen aus Textarea wie CM6:
//   data-controller="… image-paste"
//   data-action="paste->image-paste#paste"
// Text-Pastes laufen unverändert durch (nur clipboard FILES mit
// image/* werden abgefangen).
export default class extends Controller {
  async paste(event) {
    const file = Array.from(event.clipboardData?.files || [])
      .find(f => f.type.startsWith("image/"))
    if (!file) return
    event.preventDefault()
    event.stopPropagation()

    const fd = new FormData()
    fd.append("file", file, file.name || "screenshot.png")
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    let res
    try {
      res = await fetch("/knowledge_items/paste_image", {
        method: "POST", body: fd,
        headers: { "X-CSRF-Token": csrf, "Accept": "application/json" }
      })
    } catch (e) {
      console.warn("image-paste: upload failed", e)
      this._toast(window.t("image_paste.upload_failed_network"), true)
      return
    }
    if (!res.ok) {
      console.warn("image-paste: upload failed", res.status)
      this._toast(window.t("image_paste.upload_failed", { status: res.status }), true)
      return
    }
    const { title } = await res.json()
    this._insertAtCursor(`![[${title}]]`)
    // #609 v2: sichtbares Feedback — der Embed-Code steht jetzt im
    // Editor, das BILD erscheint erst nach dem Speichern (Lesemodus).
    this._toast(window.t("image_paste.created", { title: title }))
  }

  // Toast in den globalen Stack (Muster copy-clipboard/topic-tabs).
  _toast(message, error = false) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.className = `flex items-center gap-3 ${error ? "bg-rose-700" : "bg-slate-900"} text-white text-sm px-3 py-2 rounded shadow-lg`
    div.innerHTML = `<span class="flex-1 min-w-0"></span>
      <button type="button" data-action="click->toast#dismiss"
              class="${error ? "text-rose-200" : "text-slate-400"} hover:text-white text-lg leading-none">×</button>`
    div.querySelector("span").textContent = message
    stack.appendChild(div)
  }

  // Einfügen am Cursor — CM6 bevorzugt (eigene Doc-Verwaltung),
  // sonst rohe Textarea (+ input-Event, damit dirty-warn/autosize ziehen).
  _insertAtCursor(text) {
    const cm6 = this.application.getControllerForElementAndIdentifier(this.element, "cm6-editor")
    if (cm6?.view) {
      const view = cm6.view
      const { from, to } = view.state.selection.main
      view.dispatch({
        changes:   { from, to, insert: text },
        selection: { anchor: from + text.length }
      })
      view.focus()
      return
    }
    const ta = this.element.querySelector("textarea")
    if (!ta) return
    const s = ta.selectionStart ?? ta.value.length
    const e = ta.selectionEnd ?? s
    ta.value = ta.value.slice(0, s) + text + ta.value.slice(e)
    ta.selectionStart = ta.selectionEnd = s + text.length
    ta.dispatchEvent(new Event("input", { bubbles: true }))
    ta.focus()
  }
}
