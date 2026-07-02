import { Controller } from "@hotwired/stimulus"

// #239 Phase B: Inline-Popover fuer typed Wikilink-Relations.
// Wird vom „Beziehungs-Indikator"-Icon (kleines Link-Symbol neben
// einem gerenderten Wikilink) geoeffnet. Fetched die Relation per
// GET /knowledge_items/:source/relations/:anchor und rendert ein
// kompaktes Form. Save → PATCH.
//
// Markup-Konvention: das Anchor-Element hat selber die Stimulus-
// Values; der Controller injiziert das Popover absolut positioniert
// unter dem Anchor.
export default class extends Controller {
  static values = { sourceUuid: String, anchorId: String }

  connect() {
    this._popover = null
    this._closeOnDocClick = (e) => {
      if (!this._popover) return
      if (this._popover.contains(e.target) || this.element.contains(e.target)) return
      this.close()
    }
  }

  disconnect() {
    this.close()
  }

  async open(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this._popover) { this.close(); return }
    try {
      const res = await fetch(this.relationUrl, { headers: { "Accept": "application/json" } })
      if (!res.ok) { console.warn("relation fetch failed", res.status); return }
      const data = await res.json()
      this._render(data)
    } catch (err) {
      console.warn("relation fetch error", err)
    }
  }

  close() {
    if (this._popover) {
      this._popover.remove()
      this._popover = null
      document.removeEventListener("click", this._closeOnDocClick, true)
    }
  }

  get relationUrl() {
    return `/knowledge_items/${encodeURIComponent(this.sourceUuidValue)}/relations/${encodeURIComponent(this.anchorIdValue)}`
  }

  _render(data) {
    const rect = this.element.getBoundingClientRect()
    const wrap = document.createElement("div")
    wrap.className = "relation-popover fixed z-50 bg-white border border-slate-200 rounded shadow-lg p-3 w-80 text-sm"
    wrap.style.top  = `${Math.min(window.innerHeight - 16, rect.bottom + window.scrollY + 4)}px`
    wrap.style.left = `${Math.min(window.innerWidth - 332, rect.left + window.scrollX)}px`
    const datalistId = `relation-types-${Math.random().toString(36).slice(2, 8)}`
    const typeOptions = (data.relation_types || []).map(t => `<option value="${escapeHtml(t)}">`).join("")
    wrap.innerHTML = `
      <div class="flex items-center gap-2 mb-2">
        <span class="text-xs text-slate-500">${escapeHtml(window.t("relation_popover.relation_to"))}</span>
        <span class="font-medium text-slate-900 truncate" title="${escapeHtml(data.target_title)}">${escapeHtml(data.target_title)}</span>
        <button type="button" data-action="close" class="ml-auto text-slate-400 hover:text-slate-700 text-lg leading-none cursor-pointer">×</button>
      </div>
      <form class="space-y-2">
        <datalist id="${datalistId}">${typeOptions}</datalist>
        <div>
          <label class="block text-xs text-slate-500 mb-0.5">${escapeHtml(window.t("relation_popover.label"))}</label>
          <input type="text" name="label" value="${escapeHtml(data.label || "")}"
                 placeholder="${escapeHtml(window.t("relation_popover.label_placeholder"))}"
                 list="${datalistId}"
                 class="w-full rounded border border-slate-200 px-2 py-1 focus:outline-none focus:border-slate-400">
        </div>
        <div>
          <label class="block text-xs text-slate-500 mb-0.5">${escapeHtml(window.t("relation_popover.description"))}</label>
          <textarea name="description" rows="3"
                    placeholder="${escapeHtml(window.t("relation_popover.description_placeholder"))}"
                    class="w-full rounded border border-slate-200 px-2 py-1 font-mono text-xs focus:outline-none focus:border-slate-400">${escapeHtml(data.description || "")}</textarea>
        </div>
        <div class="flex items-center gap-2 text-xs">
          <label class="text-slate-500">${escapeHtml(window.t("relation_popover.direction"))}</label>
          <select name="direction" class="rounded border border-slate-200 px-1.5 py-0.5">
            <option value="source_to_target" ${data.direction === "source_to_target" ? "selected" : ""}>→</option>
            <option value="undirected" ${data.direction === "undirected" ? "selected" : ""}>—</option>
            <option value="bidirectional" ${data.direction === "bidirectional" ? "selected" : ""}>↔</option>
          </select>
          <span class="ml-auto text-slate-400">${escapeHtml(data.recognized_by || "")}</span>
        </div>
        <div class="flex items-center gap-2 pt-1">
          <button type="submit" class="px-3 py-1 rounded bg-emerald-600 text-white text-xs hover:bg-emerald-700 cursor-pointer">${escapeHtml(window.t("relation_popover.save"))}</button>
          <span class="text-xs text-slate-400">^${escapeHtml(data.anchor_id)}</span>
          ${data.orphaned_at ? `<span class="text-xs text-rose-500" title="${escapeHtml(data.orphaned_at)}">${escapeHtml(window.t("relation_popover.orphaned"))}</span>` : ""}
        </div>
      </form>
    `
    wrap.querySelector("[data-action='close']").addEventListener("click", () => this.close())
    wrap.querySelector("form").addEventListener("submit", (e) => this._save(e))
    document.body.appendChild(wrap)
    this._popover = wrap
    // Defer attaching the doc-click-listener until next tick so the
    // current click (that opened the popover) doesn't immediately close it.
    setTimeout(() => document.addEventListener("click", this._closeOnDocClick, true), 0)
  }

  async _save(event) {
    event.preventDefault()
    const form = event.currentTarget
    const fd = new FormData(form)
    const payload = {
      relation: {
        label:       fd.get("label"),
        description: fd.get("description"),
        direction:   fd.get("direction")
      }
    }
    const res = await fetch(this.relationUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify(payload)
    })
    if (res.ok) {
      this.close()
    } else {
      const err = await res.json().catch(() => ({}))
      alert(window.t("relation_popover.save_failed", { error: err.errors?.join(", ") || res.status }))
    }
  }
}

function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;")
}
