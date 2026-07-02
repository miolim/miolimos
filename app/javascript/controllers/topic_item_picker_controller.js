import { Controller } from "@hotwired/stimulus"

// #484 (Hans, 2026-06-03): Picker-Quick-Add für die Topic-Reiter. Tippen
// schlägt EXISTIERENDE KIs (des Reiter-Typs) vor (via /knowledge_items/
// suggest). Auswahl eines Treffers weist dem KI das Topic zu (POST
// /knowledge_items/:uuid/topics) und prependet die Row in die Liste. Kein
// Treffer gewählt + Enter/„Hinzufügen" -> das umschließende Form legt ein
// NEUES KI an (bekommt automatisch das Topic). Modell: task-template-picker.
//
//   <div data-controller="topic-item-picker"
//        data-topic-item-picker-url-value="/knowledge_items/suggest"
//        data-topic-item-picker-item-type-value="note"
//        data-topic-item-picker-topic-slug-value="<slug>"
//        data-topic-item-picker-list-id-value="knowledge_list">
//     <form …create…>
//       <input data-topic-item-picker-target="input"
//              data-action="input->topic-item-picker#fetch focus->topic-item-picker#fetch
//                           keydown->topic-item-picker#keydown blur->topic-item-picker#blur">
//     </form>
//     <ul data-topic-item-picker-target="list" class="hidden …"></ul>
//   </div>
export default class extends Controller {
  static targets = ["input", "list"]
  static values  = { url: String, itemType: String, topicSlug: String,
                     listId: String, topicColor: String }

  connect() {
    this._debounce = null
    this._cursor   = -1
    this._items    = null
    this._onSubmitEnd = (e) => { if (this.element.contains(e.target)) this._hide() }
    document.addEventListener("turbo:submit-end", this._onSubmitEnd)
  }

  disconnect() {
    clearTimeout(this._debounce)
    if (this._onSubmitEnd) document.removeEventListener("turbo:submit-end", this._onSubmitEnd)
  }

  fetch() {
    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => this._fetchNow(), 130)
  }

  async _fetchNow() {
    const q = this.inputTarget.value.trim()
    if (!q) { this._hide(); return }
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)
    if (this.itemTypeValue) url.searchParams.set("item_type", this.itemTypeValue)
    if (this.topicSlugValue) url.searchParams.set("topic", this.topicSlugValue)
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) { this._hide(); return }
      const data = await res.json()
      this._render(data.items || [], q)
    } catch (_) { this._hide() }
  }

  _render(items, q) {
    // Treffer + immer ein „Neu anlegen"-Eintrag am Ende. Schon zugeordnete
    // KIs (in_topic) bekommen den Topic-Farbpunkt + sind nicht klickbar.
    const dot = `<span class="w-2.5 h-2.5 rounded-full shrink-0 border border-black/10"
                       style="background:${this._esc(this.topicColorValue || "#94a3b8")}"></span>`
    const rows = items.map((it, i) => `
      <li data-index="${i}" data-uuid="${it.uuid}" ${it.in_topic ? 'data-in-topic="1"' : ""}
          class="px-3 py-1.5 text-sm border-b border-slate-100 flex items-center gap-2 ${
            it.in_topic ? "opacity-70 cursor-default" : "cursor-pointer hover:bg-emerald-50"}">
        ${it.in_topic
          ? `${dot}<span class="text-slate-400 text-[11px] shrink-0">im Thema</span>`
          : `<span class="text-emerald-700 text-xs shrink-0">+ Thema</span>`}
        <span class="font-medium text-slate-900 truncate">${this._esc(it.title)}</span>
      </li>`).join("")
    const createIdx = items.length
    const createRow = `
      <li data-index="${createIdx}" data-create="1"
          class="px-3 py-1.5 cursor-pointer text-sm hover:bg-emerald-50 flex items-center gap-2 bg-slate-50">
        <span class="text-emerald-700 text-xs shrink-0">Neu anlegen</span>
        <span class="font-medium text-slate-900 truncate">„${this._esc(q)}"</span>
      </li>`
    this.listTarget.innerHTML = rows + createRow
    this.listTarget.classList.remove("hidden")
    this._cursor = -1
    this._items = items
    this._createIndex = createIdx
    this.listTarget.querySelectorAll("li").forEach(li => {
      li.addEventListener("mousedown", (e) => {
        e.preventDefault()
        if (li.dataset.inTopic) return            // schon zugeordnet -> no-op
        if (li.dataset.create) this._createNew()
        else this._assign(li.dataset.uuid)
      })
    })
  }

  keydown(event) {
    const n = (this._items?.length || 0) + 1   // +1 für „Neu anlegen"
    if (this.listTarget.classList.contains("hidden")) return
    if (event.key === "ArrowDown") {
      event.preventDefault(); this._cursor = (this._cursor + 1) % n; this._highlight()
    } else if (event.key === "ArrowUp") {
      event.preventDefault(); this._cursor = (this._cursor - 1 + n) % n; this._highlight()
    } else if (event.key === "Enter") {
      if (this._cursor < 0) return                 // nichts gewählt -> Form legt neu an
      event.preventDefault()
      if (this._cursor === this._createIndex) this._createNew()
      else if (this._items[this._cursor]?.in_topic) return   // schon zugeordnet
      else this._assign(this._items[this._cursor].uuid)
    } else if (event.key === "Escape") {
      this._hide()
    }
  }

  _highlight() {
    this.listTarget.querySelectorAll("li").forEach((li, i) =>
      li.classList.toggle("bg-emerald-50", i === this._cursor))
  }

  // Bestehendes KI: Topic zuweisen + Row in die Liste prependen.
  async _assign(uuid) {
    if (!uuid) return
    this._hide()
    const fd = new FormData()
    fd.append("topic_id",  this.topicSlugValue)
    fd.append("tab_list",  this.listIdValue)
    fd.append("tab_topic", this.topicSlugValue)
    try {
      const res = await fetch(`/knowledge_items/${uuid}/topics`, {
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

  // Neues KI: das umschließende Create-Form abschicken.
  _createNew() {
    this._hide()
    const form = this.element.querySelector("form")
    if (form) form.requestSubmit()
  }

  _hide() {
    this.listTarget.classList.add("hidden")
    this.listTarget.innerHTML = ""
    this._items = null
    this._cursor = -1
  }

  blur() { setTimeout(() => this._hide(), 150) }

  _esc(s) {
    return String(s).replace(/[&<>"']/g, c =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }
}
