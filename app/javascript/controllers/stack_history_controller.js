import { Controller } from "@hotwired/stimulus"
import { StackSnapshotSync } from "lib/stack_snapshot_sync"

// Drawer für den Stack-Verlauf:
// - Liest localStorage (Schlüssel via storageKeyValue, Default
//   "knowledge.stack.history") aus
// - Resolved Card-Titel via POST resolveUrl mit deduplizierten UUIDs
// - Rendert pro Eintrag eine Stack-Zeile (Cards mit Chevron getrennt
//   bei breitem Viewport, untereinander auf schmal)
// - Klick auf eine Stack-Zeile: ruft blade-stack#restoreFromHistory
// - Pinning: 📌 togglet einen Eintrag als pinned (überlebt 10er-Limit)
// - × pro Eintrag: löscht ihn (gepinnte werden nicht durch "Verlauf
//   leeren" gelöscht, aber per × schon)
//
// Markup im View — siehe app/views/knowledge_items/index.html.erb.
export default class extends Controller {
  static targets = ["drawer", "list", "pinnedList", "count"]
  static values  = {
    resolveUrl: String,
    storageKey: { type: String, default: "knowledge.stack.history" },
    // #434 Teil 2: true fuer den globalen Layout-Drawer. Er entfernt sich
    // selbst, wenn die Seite bereits einen eigenen (z.B. den reichen
    // Wissens-)Drawer hat — kein Doppel-Drawer.
    shared: Boolean
  }

  // #434 Teil 2 (Hans, 2026-06-01): Der Drawer soll auf JEDEM Stack
  // funktionieren — nicht nur im Wissensbereich. Dazu:
  //  - Storage-Key vom blade-stack-Element der Seite uebernehmen, damit der
  //    Verlauf zur jeweiligen Stack-History passt (dashboard/tasks/… statt
  //    hartem knowledge.stack.history-Default).
  //  - auf ein globales `stack-history:toggle`-Event hoeren, das der
  //    Spine-Button (am Fuss jeder Card) feuert.
  connect() {
    // Globaler Layout-Drawer raeumt sich selbst weg, wenn die Seite schon
    // einen eigenen (nicht-shared) stack-history-Drawer hat (Wissen).
    if (this.sharedValue) {
      const ownDrawer = Array.from(document.querySelectorAll("[data-controller~='stack-history']"))
        .some(el => el !== this.element && el.dataset.stackHistorySharedValue !== "true")
      if (ownDrawer) { this.element.remove(); return }
    }
    // Storage-Key vom blade-stack-Element der Seite uebernehmen (dashboard/
    // tasks/… statt hartem knowledge.stack.history-Default).
    const bladeStack = this.element.closest("[data-controller~='blade-stack']") ||
                       document.querySelector("[data-controller~='blade-stack']")
    const key = bladeStack?.dataset?.bladeStackHistoryStorageKeyValue
    if (key) this.storageKeyValue = key
    // Auf das globale Toggle-Event vom Spine-Button hoeren.
    this._onToggleEvent = () => this.toggle()
    window.addEventListener("stack-history:toggle", this._onToggleEvent)
  }

  disconnect() {
    if (this._onToggleEvent) window.removeEventListener("stack-history:toggle", this._onToggleEvent)
  }

  toggle(event) {
    event?.preventDefault()
    if (this.drawerTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  async open() {
    // #434 (Hans, 2026-06-01): Storage-Key beim Oeffnen neu vom blade-stack-
    // Element lesen — der Controller koppelt den History-Bucket dynamisch an
    // das erste Listen-Blade und aktualisiert das data-Attribut entsprechend.
    const bladeStack = this.element.closest("[data-controller~='blade-stack']") ||
                       document.querySelector("[data-controller~='blade-stack']")
    const key = bladeStack?.dataset?.bladeStackHistoryStorageKeyValue
    if (key) this.storageKeyValue = key
    this.drawerTarget.classList.remove("hidden")
    this.maybeCollapseList()
    // #816: Server ist die Wahrheit — beim Öffnen die Konto-Liste ziehen
    // und den lokalen Cache ersetzen; bei Fehler (offline) lokal rendern.
    const serverEntries = await StackSnapshotSync.fetchBucket(this.storageKeyValue)
    if (serverEntries) this.writeHistory(serverEntries)
    await this.render()
  }

  // Beim Drawer-Öffnen: wenn der sichtbare Stack-Bereich nach
  // Drawer-Abzug zu schmal für eine Card wäre, klappen wir die
  // Wissens-Liste ein (idempotent, kein localStorage-Eintrag —
  // der User-Default bleibt erhalten).
  maybeCollapseList() {
    const stackArea   = this.element.clientWidth
    const drawerWidth = this.drawerTarget.offsetWidth
    const remaining   = stackArea - drawerWidth
    // Schwelle ~ Card-Breite + bisschen Luft (Card = 36rem = 576px).
    if (remaining >= 480) return

    const bladeStackEl = this.element.closest("[data-controller~=blade-stack]")
    const list        = bladeStackEl?.querySelector("aside[data-controller~=disclosure]")
    if (!list) return
    const ctl = window.Stimulus?.getControllerForElementAndIdentifier(list, "disclosure")
    ctl?.collapseIfOpen()
  }

  close() {
    this.drawerTarget.classList.add("hidden")
  }

  async render() {
    const entries = this.readHistory()
    this.countTarget.textContent = entries.length ? `${entries.length}` : ""

    // Alle UUIDs einsammeln, deduplizieren, in einem Schwung resolven.
    const allUuids = Array.from(new Set(entries.flatMap(e => this.allUuidsOf(e))))
    const titles   = await this.resolveTitles(allUuids)

    // Original-Indizes mitschleppen, damit data-history-index global
    // bleibt — Pin/Remove-Aktionen referenzieren entries[index].
    const enriched = entries.map((entry, idx) => ({ entry, idx }))
    const pinned   = enriched.filter(({ entry }) => entry.pinned)
    const recent   = enriched.filter(({ entry }) => !entry.pinned)

    if (this.hasPinnedListTarget) {
      this.pinnedListTarget.innerHTML = pinned.length
        ? pinned.map(({ entry, idx }) => this.renderEntry(entry, titles, idx)).join("")
        : `<p class="text-xs text-slate-400 italic px-2 py-2">${this.escapeHtml(window.t("stack_history.nothing_pinned"))}</p>`
    }

    this.listTarget.innerHTML = recent.length
      ? recent.map(({ entry, idx }) => this.renderEntry(entry, titles, idx)).join("")
      : `<p class="text-xs text-slate-400 italic px-2 py-2">${this.escapeHtml(window.t("stack_history.history_empty"))}</p>`

    // Klick-Handler in beiden Listen delegieren.
    const lists = [this.listTarget, this.hasPinnedListTarget ? this.pinnedListTarget : null].filter(Boolean)
    lists.forEach(parent => {
      parent.querySelectorAll("[data-history-action='open']").forEach(el => {
        el.addEventListener("click", e => { e.preventDefault(); this.openEntry(parseInt(el.dataset.historyIndex)) })
      })
      parent.querySelectorAll("[data-history-action='append']").forEach(el => {
        el.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); this.appendEntry(parseInt(el.dataset.historyIndex)) })
      })
      parent.querySelectorAll("[data-history-action='pin']").forEach(el => {
        el.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); this.togglePin(parseInt(el.dataset.historyIndex)) })
      })
      parent.querySelectorAll("[data-history-action='remove']").forEach(el => {
        el.addEventListener("click", e => { e.preventDefault(); e.stopPropagation(); this.removeEntry(parseInt(el.dataset.historyIndex)) })
      })
    })
  }

  renderEntry(entry, titles, index) {
    const trail   = entry.trail || [(entry.uuids || "").split(",").filter(Boolean)] // backward compat
    const current = entry.current ?? trail.length - 1
    const finalState = trail[current] || []
    const ago = this.timeAgo(new Date(entry.savedAt))
    const zebra = index % 2 === 0 ? "bg-white" : "bg-slate-50"
    const pinIcon = entry.pinned ? "📌" : "📍"
    const pinTitle = entry.pinned ? window.t("stack_history.unpin") : window.t("stack_history.pin")

    const cards = finalState.map(uuid => {
      const t = titles[uuid]
      // Fehlend ODER vom Resolver als unzugaenglich/geloescht markiert
      // (item_type "missing" bzw. title null) -> Platzhalter statt "null".
      if (!t || t.title == null || t.item_type === "missing") {
        return `<span class="inline-flex items-center gap-1 px-2 py-1 rounded bg-slate-200 text-xs text-slate-500 italic">🗑️ ${this.escapeHtml(window.t("stack_history.deleted"))}</span>`
      }
      // #434 (Hans, 2026-06-01): Lucide-SVG vom Server (icon_svg) bevorzugen;
      // Emoji nur noch als Fallback (z.B. KI-Drawer mit eigenem Resolver).
      const glyph = t.icon_svg
        ? `<span class="shrink-0 text-slate-500 [&>svg]:w-4 [&>svg]:h-4">${t.icon_svg}</span>`
        : this.emojiFor(t.item_type)
      return `<span class="inline-flex items-center gap-1 px-2 py-1 rounded bg-white border border-slate-200 text-xs">
                ${glyph} <span class="truncate max-w-[12rem]">${this.escapeHtml(t.title)}</span>
              </span>`
    })
    const cardsHtml = cards.join(`<span class="text-slate-300 mx-1">›</span>`)

    return `
      <div class="${zebra} border border-slate-200 rounded p-2 cursor-pointer hover:border-emerald-400 group"
           data-history-action="open" data-history-index="${index}">
        <div class="flex items-center gap-2 mb-1.5 text-[11px] text-slate-500">
          <span>${ago}</span>
          <span>·</span>
          <span>${trail.length > 1 ? window.t("stack_history.trail_position", { current: current + 1, total: trail.length }) : window.t("stack_history.note_count", { count: finalState.length })}</span>
          <button type="button" data-history-action="append" data-history-index="${index}"
                  title="${this.escapeHtml(window.t("stack_history.append_title"))}"
                  class="ml-auto p-0.5 rounded text-emerald-600 hover:bg-emerald-50 hover:text-emerald-700 text-base font-bold leading-none opacity-30 group-hover:opacity-100">+</button>
          <button type="button" data-history-action="pin" data-history-index="${index}"
                  title="${pinTitle}"
                  class="p-0.5 rounded hover:bg-slate-100 ${entry.pinned ? "" : "opacity-30 group-hover:opacity-100"}">${pinIcon}</button>
          <button type="button" data-history-action="remove" data-history-index="${index}"
                  title="${this.escapeHtml(window.t("stack_history.remove_title"))}"
                  class="p-0.5 rounded hover:bg-rose-50 hover:text-rose-700 opacity-30 group-hover:opacity-100">×</button>
        </div>
        <div class="flex flex-wrap items-center gap-y-1">
          ${cardsHtml}
        </div>
      </div>
    `
  }

  emojiFor(itemType) {
    return {
      // KI-item_types
      note: "📝", ai_chat: "🤖", web_clip: "🌐", quote: "❝", document: "📄",
      comment: "💬", person: "👤", organization: "🏢", synthesis: "🧩", reply: "💬",
      ki: "📝",
      // #434 Teil 2: Nicht-KI Stack-Kinds
      task: "📋", topic: "📁", topic_list: "📁", topic_render: "📁", topic_refs: "📁",
      ki_refs: "🔖", source: "📚", awaiting: "⏳", communication: "✉️",
      list: "📑", tag_list: "🏷️", missing: "🗑️"
    }[itemType] || "📄"
  }

  allUuidsOf(entry) {
    if (entry.trail) return entry.trail.flat()
    return (entry.uuids || "").split(",").filter(Boolean)
  }

  async resolveTitles(uuids) {
    if (uuids.length === 0) return {}
    const body = new URLSearchParams()
    uuids.forEach(u => body.append("uuids[]", u))
    const res = await fetch(this.resolveUrlValue, {
      method: "POST",
      headers: {
        "Content-Type":  "application/x-www-form-urlencoded",
        "Accept":        "application/json",
        "X-CSRF-Token":  document.querySelector("meta[name='csrf-token']")?.content
      },
      body: body.toString()
    })
    if (!res.ok) return {}
    const data = await res.json()
    const map = {}
    data.items.forEach(it => { map[it.uuid] = it })
    return map
  }

  openEntry(index) {
    const entries = this.readHistory()
    const entry = entries[index]
    if (!entry) return
    const trail   = entry.trail || [(entry.uuids || "").split(",").filter(Boolean)]
    const current = entry.current ?? trail.length - 1
    const stackCtl = this.findBladeStackController()
    if (!stackCtl) return
    this.close()
    stackCtl.restoreFromHistory(trail, current)
  }

  // #509 (Hans, 2026-06-04): Plus-Icon — den Eintrag an den AKTUELLEN Stack
  // anhängen statt ihn zu ersetzen. Hängt die Cards des finalen Trail-
  // Zustands ans Stack-Ende (schon offene werden übersprungen).
  appendEntry(index) {
    const entries = this.readHistory()
    const entry = entries[index]
    if (!entry) return
    const trail   = entry.trail || [(entry.uuids || "").split(",").filter(Boolean)]
    const current = entry.current ?? trail.length - 1
    const finalState = trail[current] || []
    const stackCtl = this.findBladeStackController()
    if (!stackCtl || typeof stackCtl.appendStackIds !== "function") return
    this.close()
    stackCtl.appendStackIds(finalState)
  }

  togglePin(index) {
    const entries = this.readHistory()
    if (!entries[index]) return
    entries[index].pinned = !entries[index].pinned
    this.writeHistory(entries)
    StackSnapshotSync.setPinned(entries[index].serverId, entries[index].pinned)  // #816
    this.render()
  }

  removeEntry(index) {
    const entries = this.readHistory()
    const [removed] = entries.splice(index, 1)
    this.writeHistory(entries)
    if (removed) StackSnapshotSync.remove(removed.serverId)  // #816
    this.render()
  }

  clear() {
    if (!confirm(window.t("stack_history.clear_confirm"))) return
    const entries = this.readHistory()
    const kept    = entries.filter(e => e.pinned)
    entries.filter(e => !e.pinned).forEach(e => StackSnapshotSync.remove(e.serverId))  // #816
    this.writeHistory(kept)
    this.render()
  }

  readHistory() {
    try { return JSON.parse(localStorage.getItem(this.storageKeyValue) || "[]") }
    catch (_) { return [] }
  }

  writeHistory(entries) {
    localStorage.setItem(this.storageKeyValue, JSON.stringify(entries))
  }

  findBladeStackController() {
    const stackEl = document.querySelector("[data-controller~=blade-stack]")
    if (!stackEl) return null
    return window.Stimulus?.getControllerForElementAndIdentifier(stackEl, "blade-stack")
  }

  timeAgo(date) {
    const sec = Math.floor((Date.now() - date.getTime()) / 1000)
    if (sec < 60)      return window.t("stack_history.just_now")
    if (sec < 3600)    return window.t("stack_history.minutes_ago", { n: Math.floor(sec / 60) })
    if (sec < 86400)   return window.t("stack_history.hours_ago", { n: Math.floor(sec / 3600) })
    return window.t("stack_history.days_ago", { n: Math.floor(sec / 86400) })
  }

  escapeHtml(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                    .replace(/"/g, "&quot;").replace(/'/g, "&#039;")
  }
}
