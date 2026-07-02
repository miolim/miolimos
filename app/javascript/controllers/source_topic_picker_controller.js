import { Controller } from "@hotwired/stimulus"

// #494 (Hans, 2026-06-03): Picker, der eine bestehende Quelle (via
// /sources/suggest) sucht und sie dem Topic zuweist (POST
// /sources/:slug/topics). Antwort ist ein turbo_stream, das die
// Recherche-Quellen-Sektion neu rendert. Modell: topic-item-picker.
export default class extends Controller {
  static targets = ["input", "list"]
  static values  = { url: String, topicId: Number, createUrl: String }

  connect() {
    this._debounce = null
    this._cursor   = -1
    this._items    = []
  }
  disconnect() { clearTimeout(this._debounce) }

  fetch() {
    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => this._fetchNow(), 130)
  }

  async _fetchNow() {
    const q = this.inputTarget.value.trim()
    if (!q) { this._hide(); return }
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) { this._hide(); return }
      const data = await res.json()
      this._render(data.items || data || [])
    } catch (_) { this._hide() }
  }

  _render(items) {
    this._items = items
    const q = this.inputTarget.value.trim()
    const rows = items.map((it, i) =>
      `<li data-index="${i}" data-slug="${this._esc(it.slug)}" ` +
      `class="px-2 py-1.5 cursor-pointer text-xs hover:bg-emerald-50 border-b border-slate-100 truncate">` +
      `<span class="text-emerald-700">+ ${this._esc(window.t("source_picker.add_topic"))}</span> ${this._esc(it.label || it.title || it.slug)}</li>`).join("")
    // #494 (Hans): „Neu anlegen"-Fuss — legt eine neue Quelle mit dem
    // getippten Titel an und nimmt sie ins Thema auf.
    this._createIndex = items.length
    const createRow = (q && this.hasCreateUrlValue)
      ? `<li data-index="${this._createIndex}" data-create="1" ` +
        `class="px-2 py-1.5 cursor-pointer text-xs hover:bg-emerald-50 bg-slate-50 truncate">` +
        `<span class="text-emerald-700">${this._esc(window.t("source_picker.create_new"))}</span> „${this._esc(q)}"</li>`
      : ""
    this.listTarget.innerHTML = rows + createRow
    if (!this.listTarget.innerHTML) { this._hide(); return }
    this.listTarget.classList.remove("hidden")
    this._cursor = -1
    this.listTarget.querySelectorAll("li").forEach(li => {
      li.addEventListener("mousedown", e => {
        e.preventDefault()
        if (li.dataset.create) this._createNew()
        else this._assign(li.dataset.slug)
      })
    })
  }

  keydown(event) {
    if (this.listTarget.classList.contains("hidden")) return
    const n = this._items.length + ((this.inputTarget.value.trim() && this.hasCreateUrlValue) ? 1 : 0)
    if (n === 0) return
    if (event.key === "ArrowDown") { event.preventDefault(); this._cursor = (this._cursor + 1) % n; this._hl() }
    else if (event.key === "ArrowUp") { event.preventDefault(); this._cursor = (this._cursor - 1 + n) % n; this._hl() }
    else if (event.key === "Enter") {
      if (this._cursor < 0) return
      event.preventDefault()
      if (this._cursor === this._createIndex) this._createNew()
      else this._assign(this._items[this._cursor].slug)
    } else if (event.key === "Escape") { this._hide() }
  }

  async _createNew() {
    const title = this.inputTarget.value.trim()
    if (!title || !this.hasCreateUrlValue) return
    this._hide()
    const fd = new FormData()
    fd.append("title", title)
    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: fd
      })
      if (res.ok) {
        const slug = res.headers.get("X-Source-Slug")
        const html = await res.text()
        if (window.Turbo && html) window.Turbo.renderStreamMessage(html)
        // #494 (Hans): die neue Quelle gleich als Blade zur Bearbeitung oeffnen.
        if (slug) {
          const stack = this._bladeStack()
          if (stack) {
            await stack.appendCard(`src:${slug}`)
            stack.restickify?.()
            stack.syncUrl?.({ pushHistory: false })
          }
        }
      }
    } catch (_) { /* still */ }
    this.inputTarget.value = ""
  }

  _bladeStack() {
    const el = document.querySelector("[data-controller~=blade-stack]")
    if (!el || !window.Stimulus) return null
    return window.Stimulus.getControllerForElementAndIdentifier(el, "blade-stack")
  }

  _hl() {
    this.listTarget.querySelectorAll("li").forEach((li, i) =>
      li.classList.toggle("bg-emerald-50", i === this._cursor))
  }

  async _assign(slug) {
    if (!slug) return
    this._hide()
    const fd = new FormData()
    fd.append("topic_id",  this.topicIdValue)
    fd.append("relevance", "relevant")
    try {
      const res = await fetch(`/sources/${encodeURIComponent(slug)}/topics`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: fd
      })
      if (res.ok) {
        const html = await res.text()
        if (window.Turbo && html) window.Turbo.renderStreamMessage(html)
      }
    } catch (_) { /* still */ }
    this.inputTarget.value = ""
  }

  _hide() {
    this.listTarget.classList.add("hidden")
    this.listTarget.innerHTML = ""
    this._items = []
    this._cursor = -1
  }

  blur() { setTimeout(() => this._hide(), 150) }

  _esc(s) {
    return String(s).replace(/[&<>"']/g, c =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }
}
