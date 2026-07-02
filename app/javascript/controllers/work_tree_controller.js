import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// #325 (Hans, 2026-05-24): Work-Tree-Tab Interaktionen. Operations:
// - addAsHeading(): Klick auf "+" eines noch unbenutzten Materials
//   → POST /topics/:slug/work_nodes mit role=heading
// - toggleRole(): wechselt heading/content fuer einen bestehenden Node
// - remove(): loescht den Node (KI bleibt unangetastet)
// - DnD (Phase 2.5): SortableJS pro list-Target. End-Handler erkennt
//   Move INNERHALB der gleichen Liste (= reorder) oder Cross-Tree
//   (= reparent) und PATCHt entsprechend.
export default class extends Controller {
  static targets = ["list", "node"]
  static values  = { topicId: Number, topicSlug: String }

  connect() {
    // Topic-Slug aus dem stack-card-Wrapper ableiten, falls nicht
    // explizit gesetzt — die URL braucht den Slug, nicht die ID.
    if (!this.hasTopicSlugValue) {
      const card = this.element.closest("[data-uuid]")
      const m = card?.dataset.uuid?.match(/^list:topic:(.+)$/)
      if (m) this.topicSlugValue = m[1]
    }
    this._sortables = []
    this.listTargets.forEach(list => this._mountSortable(list))
  }

  disconnect() {
    this._sortables?.forEach(s => s.destroy())
    this._sortables = []
  }

  _mountSortable(list) {
    const inst = Sortable.create(list, {
      group: `work-tree-${this.topicSlugValue}`,
      animation: 150,
      handle: ".cursor-grab",
      onEnd: (evt) => this._handleEnd(evt)
    })
    this._sortables.push(inst)
  }

  async _handleEnd(evt) {
    const node     = evt.item
    const fromList = evt.from
    const toList   = evt.to
    const newIndex = evt.newIndex
    if (!node?.dataset?.nodeId) return
    const nodeId    = node.dataset.nodeId
    const newParent = toList.dataset.parentId || ""
    const newPos    = newIndex + 1   // 1-based, wie WorkNodeOps#reorder
    const payload   = { position: newPos }
    if (fromList !== toList) payload.parent_id = newParent
    await this._submit("PATCH", `${this._url()}/${nodeId}`, payload)
  }

  async addAsHeading(event) {
    event.preventDefault()
    const uuid = event.currentTarget.dataset.kiUuid
    if (!uuid) return
    await this._submit("POST", this._url(), {
      knowledge_item_uuid: uuid, role: "heading"
    })
  }

  async toggleRole(event) {
    event.preventDefault()
    const li = event.currentTarget.closest("[data-node-id]")
    if (!li) return
    const newRole = li.dataset.role === "heading" ? "content" : "heading"
    await this._submit("PATCH", `${this._url()}/${li.dataset.nodeId}`, { role: newRole })
  }

  async remove(event) {
    event.preventDefault()
    if (!confirm(window.t("work_tree.confirm_remove"))) return
    const li = event.currentTarget.closest("[data-node-id]")
    if (!li) return
    await this._submit("DELETE", `${this._url()}/${li.dataset.nodeId}`)
  }

  async indent(event) {
    event.preventDefault()
    const li = event.currentTarget.closest("[data-node-id]")
    if (!li) return
    await this._submit("POST", `${this._url()}/${li.dataset.nodeId}/indent`)
  }

  async outdent(event) {
    event.preventDefault()
    const li = event.currentTarget.closest("[data-node-id]")
    if (!li) return
    await this._submit("POST", `${this._url()}/${li.dataset.nodeId}/outdent`)
  }

  // #369 (Hans, 2026-05-25): Klick auf einen Work-Tree-Eintrag scrollt
  // ein offenes Render-Blade desselben Topics an die zugehoerige Stelle
  // (Section mit `data-node-id=N`). Wenn KEIN Render-Blade offen ist,
  // ignorieren wir den Aufruf und lassen den normalen Click-Handler
  // (z.B. openInStack auf dem KI-Titel-Link) seinen Job machen.
  scrollToInRender(event) {
    const li = event.currentTarget.closest("[data-node-id]")
    if (!li) return
    const nodeId = li.dataset.nodeId
    if (!nodeId) return
    const slug = this.topicSlugValue
    const renderCard = document.querySelector(`.stack-card[data-uuid="render:topic:${CSS.escape(slug)}"]`)
    if (!renderCard) return  // kein Render-Blade offen → default click flow
    const target = renderCard.querySelector(`section[data-node-id="${CSS.escape(nodeId)}"]`)
    if (!target) return
    // default verhindern + Propagation stoppen, damit andere Actions
    // auf demselben Element (z.B. blade-stack#openInStack) NICHT
    // ausserdem feuern.
    event.preventDefault()
    event.stopImmediatePropagation()
    const stackEl = renderCard.closest("[data-controller~='blade-stack']")
    const stackCtl = stackEl && this.application.getControllerForElementAndIdentifier(stackEl, "blade-stack")
    stackCtl?.setActiveCard?.(renderCard)
    stackCtl?.scrollCardIntoView?.(renderCard)
    target.scrollIntoView({ behavior: "smooth", block: "start" })
    // #369-Fix5 (Hans, 2026-05-25 21:43): noch viel deutlicher.
    // Saturierte Farbe + 4px-Solid-Border + 3s Dauer + 3 Pulse-Ticks.
    // Plus: scroll-into-view auf die work-tree-row, damit Hans sie
    // sieht (vorher konnte sie off-screen scrollen waehrend der
    // Render-Blade-Scroll stattfindet).
    const flashRow = (el, label, scroll = false) => {
      if (!el) { console.warn("[work-tree] scrollToInRender: no", label); return }
      console.log("[work-tree] scrollToInRender flash", label, el)
      if (scroll) el.scrollIntoView({ behavior: "smooth", block: "center" })
      const orig = {
        background:  el.style.backgroundColor,
        boxShadow:   el.style.boxShadow,
        transition:  el.style.transition,
      }
      // Hard transition AUS — wir animieren via setTimeout-Pulse.
      el.style.transition  = ""
      let t = 0
      const pulse = () => {
        if (t >= 6) {
          el.style.backgroundColor = orig.background
          el.style.boxShadow       = orig.boxShadow
          el.style.transition      = orig.transition
          return
        }
        const on = (t % 2 === 0)
        el.style.backgroundColor = on ? "rgba(251, 191, 36, 0.85)" : "transparent"
        el.style.boxShadow       = on ? "0 0 0 4px rgb(220 38 38) inset" : "none"
        t++
        setTimeout(pulse, 250)
      }
      pulse()
    }
    const headerEl = target.querySelector(":scope > header") || target
    const liHeader = li.querySelector(":scope > div") || li
    flashRow(headerEl, "render-header")
    flashRow(liHeader, "work-tree-row", true)
  }

  async _submit(method, url, params = {}) {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    const fd = new FormData()
    Object.entries(params).forEach(([k, v]) => fd.append(k, v))
    if (method !== "POST") fd.append("_method", method)
    const res = await fetch(url, {
      method: method === "DELETE" ? "POST" : method,
      body: fd,
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrf
      }
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      alert(window.t("work_tree.update_failed", { error: err.error || res.status }))
      return
    }
    const html = await res.text()
    // Turbo-Stream-Antwort im DOM anwenden — verwende Turbo direkt.
    if (window.Turbo) {
      window.Turbo.renderStreamMessage(html)
    } else {
      // Fallback: kompletten Card-Tausch via DOMParser
      const tpl = document.createElement("template")
      tpl.innerHTML = html.trim()
      tpl.content.querySelectorAll("turbo-stream").forEach(s => {
        const target = document.getElementById(s.getAttribute("target"))
        if (!target) return
        const inner = s.querySelector("template").content
        if (s.getAttribute("action") === "replace") target.replaceWith(inner.cloneNode(true))
      })
    }
  }

  _url() {
    return `/topics/${encodeURIComponent(this.topicSlugValue)}/work_nodes`
  }
}
