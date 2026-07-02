import { Controller } from "@hotwired/stimulus"

// #497 (Hans, 2026-06-03): Suchschlitz in der Antworten-Section. Tippen
// filtert den Thread client-seitig (alle Antworten liegen im DOM):
//  - zeigt die Trefferzahl + Anzahl betroffener Antworten,
//  - blendet Antworten OHNE Treffer aus,
//  - in Treffer-Antworten nur die Treffer-Bloecke + je einen Block davor/
//    danach (Kontext), Rest ausgeblendet,
//  - hebt die Fundstellen hervor (<mark>),
//  - klappt eingeklappte Treffer (Disclosure: „Aeltere Antworten" + der
//    Antwort-Body) automatisch auf.
// Leeres Feld stellt den Originalzustand wieder her.
// #615 (Hans): verallgemeinert auf den CARD-Scope — mit
// data-reply-search-scope-value="card" sucht der Schlitz über die GANZE
// Karte: Beschreibung/KI-Body (Flächen mit data-card-search-area) UND
// alle Antworten. Ohne scope bleibt das Verhalten der Thread-Suche.
export default class extends Controller {
  static targets = ["input", "status", "mode"]
  // #782 (Hans): highlightColors = aktive ?hl=-Farben. Gesetzt → der Modus-
  // Button filtert die Highlights (statt Suchtreffer); leer → Suche wie bisher.
  static values  = { scope: String, highlightColors: Array }

  // #615 v3 (Hans): Anzeige-Modus — rotiert über EIN Icon.
  //   all     = Alles anzeigen (nur markieren, nichts ausblenden)
  //   context = Absätze mit Treffer ±1 (bisheriges Verhalten, Default)
  //   hits    = Nur Absätze mit Treffer
  //   mark    = #782: NUR die Hervorhebung selbst (bare Mark) — nur im
  //             Highlight-Modus sinnvoll.
  // #782 (Hans): Im Highlight-Modus rotiert der Button über context → hits →
  // mark (Stufen 2/3/4); „Alles" (Stufe 1) erreicht man durchs Abwählen der
  // Highlight-Farbe. In der Textsuche bleibt es bei all/context/hits.
  static MODES    = ["all", "context", "hits"]
  static HL_MODES = ["context", "hits", "mark"]
  static MODE_UI = {
    all:     { titleKey: "reply_search.mode_all",
               svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="4" y1="6" x2="20" y2="6"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="18" x2="20" y2="18"/></svg>' },
    context: { titleKey: "reply_search.mode_context",
               svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="4" y1="6" x2="20" y2="6" opacity="0.35"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="18" x2="20" y2="18" opacity="0.35"/></svg>' },
    hits:    { titleKey: "reply_search.mode_hits",
               svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="4" y1="12" x2="20" y2="12"/></svg>' },
    // #782: kurzer, dicker Strich = nur die Markierung selbst.
    mark:    { titleKey: "reply_search.mode_mark",
               svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round"><line x1="9" y1="12" x2="15" y2="12"/></svg>' }
  }

  connect() {
    this._debounce = null
    // #615 v3: Modus global gemerkt (eine Vorliebe, nicht pro Karte).
    this._mode = localStorage.getItem("replySearch.mode") || "context"
    this._normalizeMode()   // #782: passend zum aktiven Set (Suche vs. Highlight)
    this._renderModeButton()
    // Original-innerHTML jeder Antwort-Markdown-Flaeche cachen (fuer Restore
    // + um Highlights idempotent neu zu setzen).
    this._cache = new Map()
    this._cards().forEach(card => {
      const mb = this._markdownBody(card)
      if (mb) this._cache.set(card, mb.innerHTML)
    })
    // #497: Aufklapp-Button („ganze Antwort zeigen") — delegiert, weil die
    // Buttons bei jeder Suche neu erzeugt werden. Suche bleibt erhalten.
    this._onExpandClick = (e) => {
      const btn = e.target.closest("[data-reply-search-expand]")
      if (!btn || !this.element.contains(btn)) return
      e.preventDefault()
      const mb = btn.closest(".markdown-body")
      if (!mb) return
      const hidden = mb.querySelectorAll("[data-reply-search-hidden]")
      if (hidden.length) {
        const lc = this.inputTarget.value.trim().toLowerCase()
        hidden.forEach(b => {
          b.style.display = ""
          b.removeAttribute("data-reply-search-hidden")
          if (lc) this._highlight(b, lc)
        })
        btn.remove()                 // ganze Antwort gezeigt -> Button weg
      }
    }
    document.addEventListener("click", this._onExpandClick)
    // #782: bei aktivem Highlight-Filter sofort anwenden (auch ohne Suchtext).
    if (this._hlColors().length) this._apply()
  }

  // #782: aktive Highlight-Farben (Array), defensiv.
  _hlColors() {
    return this.hasHighlightColorsValue ? (this.highlightColorsValue || []) : []
  }

  disconnect() {
    clearTimeout(this._debounce)
    if (this._onExpandClick) document.removeEventListener("click", this._onExpandClick)
  }

  search() {
    clearTimeout(this._debounce)
    this._forceShort = false   // Tippen hebt einen erzwungenen Kurz-Suchlauf auf
    this._debounce = setTimeout(() => this._apply(), 120)
  }

  // #653 (Hans): 1-2 Zeichen suchen nur auf expliziten Klick aufs
  // Such-Icon — sonst blendet schon das erste getippte "a" alles um.
  forceSearch() {
    clearTimeout(this._debounce)
    this._forceShort = true
    this._apply()
  }

  // #615 v3 / #782: Klick rotiert im jeweils aktiven Set — Suche:
  // all→context→hits; Highlight: context→hits→mark.
  cycleMode() {
    this._normalizeMode()
    const set = this._modeSet()
    this._mode = set[(set.indexOf(this._mode) + 1) % set.length]
    localStorage.setItem("replySearch.mode", this._mode)
    this._renderModeButton()
    this._apply()
  }

  // #782: aktives Modus-Set — Highlight-Set, wenn ein Highlight-Filter aktiv
  // ist und kein Suchtext getippt wurde; sonst das Such-Set.
  _modeSet() {
    const hl = this._hlColors().length > 0 && !this.inputTarget.value.trim()
    return hl ? this.constructor.HL_MODES : this.constructor.MODES
  }

  // #782: liegt der gemerkte Modus nicht im aktiven Set (z.B. „mark" in der
  // Suche oder „all" im Highlight-Modus), auf „context" normalisieren.
  _normalizeMode() {
    const set = this._modeSet()
    if (!set.includes(this._mode)) this._mode = "context"
  }

  _renderModeButton() {
    if (!this.hasModeTarget) return
    const ui = this.constructor.MODE_UI[this._mode]
    this.modeTarget.innerHTML = ui.svg
    this.modeTarget.title = window.t(ui.titleKey)
  }

  _cards() {
    const root = this.scopeValue === "card"
      ? (this.element.closest(".stack-card") || this.element)
      : this.element
    const areas = this.scopeValue === "card"
      ? Array.from(root.querySelectorAll("[data-card-search-area]"))
      : []
    return areas.concat(Array.from(root.querySelectorAll("li[id^='reply_']")))
  }

  // Beschreibungs-Flächen SIND die markdown-body; Antworten wrappen sie.
  _markdownBody(card) {
    return card.matches?.(".markdown-body") ? card : card.querySelector(".markdown-body")
  }

  _apply() {
    let q = this.inputTarget.value.trim()
    // #653: unter 3 Zeichen erst auf expliziten Wunsch filtern.
    const tooShort = q.length > 0 && q.length < 3 && !this._forceShort
    if (tooShort) q = ""
    const lc = q.toLowerCase()
    let total = 0, repliesHit = 0
    // #782: ohne Suchtext, aber mit aktivem Highlight-Filter → Highlight-Modus.
    const hlColors = this._hlColors()
    const useHl = !q && hlColors.length > 0
    // #782: Modus passend zum aktiven Set halten (Such- vs. Highlight-Set).
    this._normalizeMode()
    this._renderModeButton()

    // #497: Der Such-Schlitz sitzt in der (immer sichtbaren) Titelzeile —
    // bei aktiver Suche (oder Highlight-Filter) die Section aufklappen.
    if (q || useHl) {
      const own = this.application?.getControllerForElementAndIdentifier(this.element, "disclosure")
      own?.expand?.()
    }

    this._cards().forEach(card => {
      const mb = this._markdownBody(card)
      if (!mb) return
      // #782: Im Highlight-Modus nur die Body-Flächen filtern; Antworten
      // behalten ihren serverseitigen Highlight-Filter (#450).
      if (useHl && !card.matches?.("[data-card-search-area]")) return
      // Immer erst auf Original zuruecksetzen (alte Highlights/Block-Hides weg).
      const orig = this._cache.get(card)
      if (orig != null) mb.innerHTML = orig
      this._showCard(card, true)
      mb.querySelectorAll("[data-reply-search-hidden]").forEach(b => {
        b.style.display = ""
        b.removeAttribute("data-reply-search-hidden")
      })

      if (!q && !useHl) return

      const blocks = Array.from(mb.children)
      const hitIdx = []
      blocks.forEach((b, i) => {
        const n = useHl ? this._countHl(b, hlColors) : this._count(b.textContent, lc)
        if (n > 0) { hitIdx.push(i); total += n }
      })

      if (hitIdx.length === 0) {
        // #615 v3: im Alles-Modus bleiben auch trefferlose Antworten stehen.
        this._showCard(card, this._mode === "all")
        return
      }
      repliesHit++

      // #615 v3: Sichtbarkeit nach Modus — all: nichts ausblenden,
      // context: Treffer ±1 (Default), hits: nur Treffer-Bloecke.
      if (this._mode === "all") {
        // Highlight-Marks sind schon im DOM; nur Suchtreffer extra markieren.
        if (!useHl) blocks.forEach(b => this._highlight(b, lc))
        this._expandAncestors(card)
        return
      }
      const visible = new Set()
      hitIdx.forEach(i => {
        if (this._mode === "context") { visible.add(i - 1); visible.add(i + 1) }
        visible.add(i)
      })
      let hidden = 0
      blocks.forEach((b, i) => {
        if (!visible.has(i)) {
          b.style.display = "none"
          b.setAttribute("data-reply-search-hidden", "1")
          hidden++
        } else if (useHl && this._mode === "mark") {
          // #782 Stufe 4: nur die Markierung selbst — den Block auf seine
          // aktiven Marks reduzieren (Resttext weg).
          const ms = [...b.querySelectorAll(this._hlSelector(hlColors))]
          if (ms.length) b.innerHTML = ms.map(m => m.outerHTML).join("  ")
        } else if (!useHl) {
          this._highlight(b, lc)
        }
      })
      if (hidden > 0) {
        if (useHl) {
          // #782: serverseitigen #673-Effekt nachbauen — „N Wörter dazwischen".
          this._insertWordGaps(mb, blocks, visible)
        } else {
          // #497 (Hans): „mehr Kontext bei Bedarf, ohne die Suche zu verlieren".
          const mb2 = this._markdownBody(card)
          const btn = document.createElement("button")
          btn.type = "button"
          btn.setAttribute("data-reply-search-expand", "")
          btn.className = "reply-search-expand block mt-1 text-[11px] text-amber-700 hover:underline cursor-pointer"
          btn.textContent = window.t("reply_search.show_more", { count: hidden })
          mb2.appendChild(btn)
        }
      }
      this._expandAncestors(card)
    })

    // #615/#616 (Hans): die innerHTML-Manipulation oben erzeugt frische
    // Block-Nodes — Kontextmenü/Hover (paragraph-actions) hingen an den
    // alten und waren nach jeder Suche tot. Re-dekorieren — auch beim
    // LEEREN des Felds (Restore erzeugt ebenfalls frische Nodes).
    this._redecorateParagraphActions()

    if (q) {
      const noun = this.scopeValue === "card"
        ? (repliesHit === 1 ? window.t("reply_search.noun_place") : window.t("reply_search.noun_places"))
        : (repliesHit === 1 ? window.t("reply_search.noun_reply") : window.t("reply_search.noun_replies"))
      this.statusTarget.textContent =
        total === 0 ? window.t("reply_search.no_hits") : window.t("reply_search.hits_summary", { total: total, count: repliesHit, noun: noun })
    } else if (useHl) {
      // #782: Status im Highlight-Modus — Anzahl Hervorhebungen.
      this.statusTarget.textContent =
        total === 0 ? window.t("reply_search.no_hits") : window.t("reply_search.hl_summary", { total: total })
    } else {
      this.statusTarget.textContent = tooShort ? window.t("reply_search.min_chars_hint") : ""
    }
  }

  // #782: CSS-Selektor für die aktiven Highlight-Farben.
  _hlSelector(colors) {
    return colors.map(c => `mark.hl-${c}`).join(",")
  }

  // #782: Highlights einer aktiven Farbe in einem Block zaehlen.
  _countHl(block, colors) {
    if (!colors.length) return 0
    return block.querySelectorAll(this._hlSelector(colors)).length
  }

  // #782: zwischen nicht-benachbarten sichtbaren Bloecken die Anzahl der
  // ausgeblendeten Woerter einblenden (ersetzt den serverseitigen #673-Effekt).
  _insertWordGaps(mb, blocks, visible) {
    const vis = blocks.map((_, i) => i).filter(i => visible.has(i))
    for (let k = 1; k < vis.length; k++) {
      const prev = vis[k - 1], cur = vis[k]
      if (cur - prev <= 1) continue
      let words = 0
      for (let j = prev + 1; j < cur; j++) {
        words += (blocks[j].textContent.match(/\S+/g) || []).length
      }
      if (words > 0) blocks[cur].parentNode.insertBefore(this._wordGap(words), blocks[cur])
    }
  }

  _wordGap(n) {
    const div = document.createElement("div")
    div.className = "hl-words-between flex items-center gap-2 my-2 text-[11px] text-slate-400 select-none"
    const label = n === 1 ? window.t("reply_search.words_between_one")
                          : window.t("reply_search.words_between", { count: n })
    div.innerHTML = '<span class="flex-1 border-t border-slate-200"></span>' +
                    `<span class="italic">${label}</span>` +
                    '<span class="flex-1 border-t border-slate-200"></span>'
    return div
  }

  _showCard(card, show) { card.style.display = show ? "" : "none" }

  // #615/#616: paragraph-actions im Such-Wurzelbereich neu dekorieren.
  _redecorateParagraphActions() {
    const root = this.scopeValue === "card"
      ? (this.element.closest(".stack-card") || this.element)
      : this.element
    root.querySelectorAll('[data-controller~="paragraph-actions"]').forEach(el => {
      const c = this.application.getControllerForElementAndIdentifier(el, "paragraph-actions")
      c?.redecorateAfterMorph?.()
    })
  }

  _count(text, lc) {
    if (!lc) return 0
    const hay = text.toLowerCase()
    let i = 0, n = 0
    while ((i = hay.indexOf(lc, i)) !== -1) { n++; i += lc.length }
    return n
  }

  // Fundstellen in einem Block in <mark> wrappen — ueber Textknoten, damit
  // Kindelemente (Links etc.) intakt bleiben.
  _highlight(block, lc) {
    if (!lc) return
    const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, null)
    const targets = []
    let node
    while ((node = walker.nextNode())) {
      if (node.nodeValue.toLowerCase().includes(lc)) targets.push(node)
    }
    targets.forEach(textNode => {
      const text = textNode.nodeValue
      const frag = document.createDocumentFragment()
      const low = text.toLowerCase()
      let i = 0, m
      while ((m = low.indexOf(lc, i)) !== -1) {
        if (m > i) frag.appendChild(document.createTextNode(text.slice(i, m)))
        const mark = document.createElement("mark")
        mark.className = "reply-search-hit bg-amber-200 rounded-sm"
        mark.textContent = text.slice(m, m + lc.length)
        frag.appendChild(mark)
        i = m + lc.length
      }
      if (i < text.length) frag.appendChild(document.createTextNode(text.slice(i)))
      textNode.parentNode.replaceChild(frag, textNode)
    })
  }

  // Eingeklappte Disclosure-Vorfahren (Aeltere-Antworten-Wrapper + der
  // Antwort-Body) aufklappen, damit der Treffer sichtbar ist.
  _expandAncestors(card) {
    let el = card
    while (el && el !== this.element) {
      if (el.dataset && (el.dataset.controller || "").split(/\s+/).includes("disclosure")) {
        const ctrl = this.application?.getControllerForElementAndIdentifier(el, "disclosure")
        ctrl?.expand?.()
      }
      el = el.parentElement
    }
  }
}
