import { Controller } from "@hotwired/stimulus"

// #301: KI-Vorlagen-Picker fuer den Quick-Create-KI-Slot. Analog
// task-template-picker, fuellt aber drei Felder: item_type (Select),
// title (Input) und body (Hidden). Tippen filtert /ki_templates/suggest.
export default class extends Controller {
  static targets = ["input", "list"]
  static values  = {
    itemTypeTargetId: String,
    titleTargetId:    String,
    bodyTargetId:     String
  }

  connect() {
    this._debounce = null
    this._cursor   = -1
    // #313 (analog Task-Picker): nach erfolgreichem Submit Dropdown
    // ausblenden — das <ul> ueberlebt sonst den Form-Replace.
    this._onSubmitEnd = (e) => {
      if (this.element.contains(e.target) && e.detail?.success) {
        this._hide()
      }
    }
    document.addEventListener("turbo:submit-end", this._onSubmitEnd)

    // #313 follow-up (Mobile): bei horizontalem Swipe zwischen Blade-
    // Cards bleibt das Dropdown sonst sichtbar. Scroll-Events von
    // allen scrollbaren Vorfahren raeumen es auf.
    this._onAncestorScroll = () => this._hide()
    this._scrollAncestors = this._findScrollAncestors()
    this._scrollAncestors.forEach(el => el.addEventListener("scroll", this._onAncestorScroll, { passive: true }))
  }

  disconnect() {
    clearTimeout(this._debounce)
    if (this._onSubmitEnd) document.removeEventListener("turbo:submit-end", this._onSubmitEnd)
    this._scrollAncestors?.forEach(el => el.removeEventListener("scroll", this._onAncestorScroll))
  }

  _findScrollAncestors() {
    const ancestors = []
    let el = this.element.parentElement
    while (el && el !== document.body) {
      const cs = getComputedStyle(el)
      if (cs.overflowX === "auto" || cs.overflowX === "scroll" ||
          cs.overflowY === "auto" || cs.overflowY === "scroll") {
        ancestors.push(el)
      }
      el = el.parentElement
    }
    return ancestors
  }

  fetch() {
    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => this._fetchNow(), 120)
  }

  async _fetchNow() {
    const q = this.inputTarget.value.trim()
    const url = new URL("/ki_templates/suggest", window.location.origin)
    if (q) url.searchParams.set("q", q)
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) { this._hide(); return }
      this._render(await res.json())
    } catch (e) {
      this._hide()
    }
  }

  _render(items) {
    if (!items || items.length === 0) { this._hide(); return }
    this.listTarget.innerHTML = items.map((t, i) => `
      <li data-index="${i}" data-id="${t.id}"
          class="px-3 py-1.5 cursor-pointer text-sm hover:bg-sky-50 border-b border-slate-100 last:border-b-0">
        <div class="flex items-center gap-2">
          <span class="font-medium text-slate-900 truncate">${this._esc(t.name)}</span>
          <span class="shrink-0 inline-flex items-center px-1 py-0 rounded bg-sky-50 border border-sky-200 text-sky-800 text-[10px] uppercase">${this._esc(t.item_type)}</span>
        </div>
        ${t.title ? `<div class="text-[11px] text-slate-500 truncate">${this._esc(t.title)}</div>` : ""}
      </li>
    `).join("")
    this.listTarget.classList.remove("hidden")
    this._cursor = -1
    this.listTarget.querySelectorAll("li").forEach(li => {
      li.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this._pick(parseInt(li.dataset.id, 10))
      })
    })
    this._items = items
  }

  _hide() {
    this.listTarget.classList.add("hidden")
    this.listTarget.innerHTML = ""
    this._items = null
    this._cursor = -1
  }

  _esc(s) {
    return String(s).replace(/[&<>"']/g, c => (
      { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
    ))
  }

  keydown(event) {
    if (!this._items || this._items.length === 0) return
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this._cursor = (this._cursor + 1) % this._items.length
      this._highlight()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this._cursor = (this._cursor - 1 + this._items.length) % this._items.length
      this._highlight()
    } else if (event.key === "Enter" && this._cursor >= 0) {
      event.preventDefault()
      this._pick(this._items[this._cursor].id)
    } else if (event.key === "Escape") {
      this._hide()
    }
  }

  _highlight() {
    this.listTarget.querySelectorAll("li").forEach((li, i) => {
      li.classList.toggle("bg-sky-50", i === this._cursor)
    })
  }

  _pick(id) {
    const tpl = (this._items || []).find(t => t.id === id)
    if (!tpl) return
    const typeEl  = document.getElementById(this.itemTypeTargetIdValue)
    const titleEl = document.getElementById(this.titleTargetIdValue)
    const bodyEl  = document.getElementById(this.bodyTargetIdValue)
    if (typeEl)  typeEl.value  = tpl.item_type
    if (titleEl) titleEl.value = tpl.title || ""
    if (bodyEl)  bodyEl.value  = tpl.body  || ""
    if (titleEl !== this.inputTarget) this.inputTarget.value = ""
    this._hide()
    const focusEl = titleEl || this.inputTarget
    if (focusEl) {
      focusEl.focus?.()
      if (typeof focusEl.value === "string") {
        const v = focusEl.value
        focusEl.value = ""
        focusEl.value = v
      }
    }
  }

  blur() {
    setTimeout(() => this._hide(), 150)
  }
}
