import { Controller } from "@hotwired/stimulus"

// #299: Aufgabenvorlagen-Picker fuer das Quickadd-Formular. Tippen in
// das Input filtert Vorlagen via /task_templates/suggest, Klick auf
// einen Treffer fuellt Title- und Description-Felder der Form. Der
// Picker bleibt klein/dezent — analog wikilink-autocomplete: schmale
// Liste direkt unter dem Input, Tastatur-Navigation (↑↓ Enter Esc).
//
// Markup:
//   <div data-controller="task-template-picker"
//        data-task-template-picker-agent-id-value="<%= agent_id %>"
//        data-task-template-picker-title-target-id-value="task_title_field"
//        data-task-template-picker-description-target-id-value="task_description_field">
//     <input type="text" data-task-template-picker-target="input"
//            data-action="input->task-template-picker#fetch focus->task-template-picker#fetch
//                         keydown->task-template-picker#keydown
//                         blur->task-template-picker#blur"
//            placeholder="Vorlage suchen …">
//     <ul data-task-template-picker-target="list" class="hidden ..."></ul>
//   </div>
export default class extends Controller {
  static targets = ["input", "list"]
  static values  = {
    agentId:              String,
    titleTargetId:        String,
    descriptionTargetId:  String
  }

  connect() {
    this._debounce = null
    this._cursor   = -1
    // #313: nach erfolgreichem Form-Submit das Dropdown ausblenden.
    // Der Form selbst wird vom Controller per turbo_stream.replace neu
    // gerendert, aber das <ul> liegt AUSSERHALB des Forms (innerhalb
    // unseres Controllers) und bleibt sonst stehen — Hans sah die
    // Trefferliste auch nach Anlegen der Aufgabe noch dauerhaft.
    this._onSubmitEnd = (e) => {
      if (this.element.contains(e.target) && e.detail?.success) {
        this._hide()
      }
    }
    document.addEventListener("turbo:submit-end", this._onSubmitEnd)

    // #313 follow-up (Hans, Mobile): wenn der User horizontal
    // zwischen Blade-Cards swiped, scrollt der naechste sichtbare
    // Container — der Picker bleibt aber offen. Wir hoeren auf
    // Scroll-Events am naechstgelegenen scrollbaren Vorfahren UND
    // am Stack-Container (blade-stack) und blenden dann aus.
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
    const url = new URL("/task_templates/suggest", window.location.origin)
    if (q) url.searchParams.set("q", q)
    if (this.agentIdValue) url.searchParams.set("agent_id", this.agentIdValue)
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) { this._hide(); return }
      const items = await res.json()
      this._render(items)
    } catch (e) {
      this._hide()
    }
  }

  _render(items) {
    if (!items || items.length === 0) {
      this._hide()
      return
    }
    this.listTarget.innerHTML = items.map((t, i) => `
      <li data-index="${i}" data-id="${t.id}"
          class="px-3 py-1.5 cursor-pointer text-sm hover:bg-emerald-50 border-b border-slate-100 last:border-b-0">
        <div class="flex items-center gap-2">
          <span class="font-medium text-slate-900 truncate">${this._esc(t.title)}</span>
          ${t.agent_name ? `<span class="shrink-0 inline-flex items-center px-1 py-0 rounded bg-emerald-50 border border-emerald-200 text-emerald-800 text-[10px] uppercase">${this._esc(t.agent_name)}</span>` : ""}
        </div>
        ${t.description ? `<div class="text-[11px] text-slate-500 truncate">${this._esc(t.description)}</div>` : ""}
      </li>
    `).join("")
    this.listTarget.classList.remove("hidden")
    this._cursor = -1
    // Click-Delegation
    this.listTarget.querySelectorAll("li").forEach(li => {
      // mousedown statt click — sonst feuert vorher der blur und versteckt
      // die Liste, bevor wir das Click-Event verarbeiten koennen.
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
      li.classList.toggle("bg-emerald-50", i === this._cursor)
    })
  }

  _pick(id) {
    const tpl = (this._items || []).find(t => t.id === id)
    if (!tpl) return
    const titleEl = document.getElementById(this.titleTargetIdValue)
    const descEl  = document.getElementById(this.descriptionTargetIdValue)
    if (titleEl) {
      titleEl.value = tpl.title
      titleEl.dispatchEvent(new Event("input", { bubbles: true }))
    }
    if (descEl) {
      descEl.value = tpl.description || ""
      descEl.dispatchEvent(new Event("input", { bubbles: true }))
    }
    // Wenn der Picker-Input ein separates Feld ist, leeren wir es;
    // wenn er IDENTISCH mit dem Title-Feld ist (Inline-Picker im
    // Quickadd), bleibt der Wert stehen.
    if (titleEl !== this.inputTarget) this.inputTarget.value = ""
    this._hide()
    // Cursor in das relevanteste Feld: Description (wenn nicht-hidden
    // + befuellt), sonst Title, sonst Input.
    const target = (descEl && tpl.description && descEl.type !== "hidden") ? descEl
                 : (titleEl || this.inputTarget)
    if (target) {
      target.focus?.()
      if (typeof target.value === "string") {
        const v = target.value
        target.value = ""
        target.value = v   // cursor ans Ende
      }
    }
  }

  blur() {
    // setTimeout, damit der mousedown auf einem List-Item noch durchgeht.
    setTimeout(() => this._hide(), 150)
  }
}
