import { Controller } from "@hotwired/stimulus"
import { BacklinksPopover } from "lib/backlinks_popover"

// Hover-Iconbar für jeden referenzierbaren Block (`<p>`, `<li>`,
// `<blockquote>`) in einer Knowledge-Card. Beim Hover erscheint rechts
// oben am Block eine kleine Toolbar mit:
//   📋  Link in die Zwischenablage kopieren
//   💬  Comment-KI an diesem Anker erzeugen + im Stack daneben öffnen
// Wenn der Block bereits einen stabilen Anker hat (id = `[a-z0-9-]{2,}`,
// nicht `block-N`), zusätzlich ein 🔗-Indicator, der dauerhaft sichtbar
// bleibt. Klick öffnet einen Backlinks-Popover.
//
// Markup:
//   <div data-controller="paragraph-actions"
//        data-paragraph-actions-uuid-value="<uuid>">
//     <article class="markdown-body">
//       <p id="block-1">…</p>
//       <p id="my-stable-id">…</p>
//     </article>
//   </div>
export default class extends Controller {
  // #466 (Hans, 2026-06-02): reply=true → der Absatz-Link nutzt den
  // Parent-Titel (KI-Heading) als Ziel und „Thread-Antwort" als Alternate-
  // Display: [[Parent^anker|Thread-Antwort]].
  // #480 Inc.2 (Hans, 2026-06-03): base = Endpoint-Basis. Default
  // /knowledge_items/<uuid>; fuer eine Task-Description /tasks/<id>.
  // surface = "task" blendet die (noch) nicht task-faehigen Aktionen aus
  // (Link/Kommentar/Aufgabe/Recherche/Mark-Tags) — Highlight bleibt.
  static values = { uuid: String, title: String, reply: Boolean,
                    base: String, surface: String }

  // Endpoint-Basis (KI oder Task).
  get _base() {
    return (this.hasBaseValue && this.baseValue) ? this.baseValue
                                                 : `/knowledge_items/${this.uuidValue}`
  }
  get _isTaskSurface() { return this.surfaceValue === "task" }

  connect() {
    // #387/#232 Folgefix: WeakSet der bereits augmentierten Bloecke. Eine
    // Block-Node ueberlebt einen Turbo-Morph (idiomorph erhaelt Elemente per
    // id), die Controller-Instanz ebenfalls — so koennen wir nach einem
    // Morph gezielt RE-dekorieren statt Listener doppelt zu wiren.
    this._augmentedBlocks ||= new WeakSet()

    const article = this.element.querySelector(".markdown-body")
    if (!article) return

    // #341 (Hans, 2026-05-24): Headings sind jetzt auch anker-faehig
    // — h1..h6 mit auf die Liste.
    article.querySelectorAll("p[id], li[id], blockquote[id], h1[id], h2[id], h3[id], h4[id], h5[id], h6[id], .hl-filter-block").forEach(block => {
      this.augment(block)
    })

    // #232 Phase 1-3 (B) Folgefix: Ein Refresh-Morph rendert die Bloecke auf
    // das Server-HTML zurueck — dabei gehen die client-seitig in augment()
    // gesetzten Klassen (para-anchorable, relative, group/block) verloren und
    // die an document.body gehaengten .para-actions-Bars werden entfernt.
    // connect() feuert nach einem Morph NICHT neu (Element bleibt erhalten),
    // daher auf turbo:render hoeren und re-dekorieren. (Das war die Ursache
    // fuer #387: nach einem Live-Update waren Hover-Highlight + Right-Click-
    // Menue tot, weil der alte contextmenu-Listener zwar ueberlebte, seine
    // Bar aber aus dem DOM entfernt war.)
    this._onTurboRender = () => this.redecorateAfterMorph()
    document.addEventListener("turbo:render", this._onTurboRender)
  }

  augment(block) {
    this._augmentedBlocks ||= new WeakSet()
    this._augmentedBlocks.add(block)
    block.classList.add("para-anchorable", "relative", "group/block")

    // #365 Phase 4 (Hans, 2026-05-28): Bar wird per Rechtsklick /
    // Long-Press an Mausposition positioniert (kein Hover-Hot-Zone
    // mehr — die ueberlappten bei eng aneinander liegenden Bloecken).
    // Position: fixed mit inline-styles top/left; Sichtbarkeit per
    // hidden-Attribut.
    const bar = document.createElement("div")
    bar.className = "para-actions fixed z-50 flex flex-col items-stretch " +
                    "bg-white border border-slate-200 rounded shadow-md text-slate-500"
    bar.hidden = true

    // Lucide-Icons mit stroke-width 1.5 — gleicher Look wie alle
    // restlichen Icons (siehe ApplicationHelper#icon und shared/icons/).
    const ICON_ATTRS = `xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"`
    // #365 Phase 3 (Hans, 2026-05-25): Color-Picker-Zeile UEBER den
    // bestehenden Icons. Klick auf eine Farbe wraps den ganzen Absatz
    // in `==color|text==` (persistiert in der KI-Body-File).
    const colorBtn = (color, bg, hover) => `
      <button type="button" title="${window.t("js.paragraph.highlight_paragraph", { color })}" data-action="color" data-color="${color}"
              class="w-5 h-5 rounded ${bg} ${hover} border border-slate-200">
      </button>`
    bar.innerHTML = `
      <div class="flex items-center gap-0.5 px-0.5 py-0.5 border-b border-slate-200 w-full justify-start">
        ${colorBtn("gelb",   "bg-amber-200",   "hover:bg-amber-300")}
        ${colorBtn("rot",    "bg-rose-200",    "hover:bg-rose-300")}
        ${colorBtn("gruen",  "bg-emerald-200", "hover:bg-emerald-300")}
        ${colorBtn("blau",   "bg-sky-200",     "hover:bg-sky-300")}
        ${colorBtn("lila",   "bg-violet-200",  "hover:bg-violet-300")}
        <button type="button" title="${window.t("js.paragraph.highlight_remove")}" data-action="color" data-color="keine"
                class="w-5 h-5 rounded bg-white hover:bg-slate-100 border border-slate-200 flex items-center justify-center text-slate-500">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <circle cx="12" cy="12" r="10"/>
            <line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
          </svg>
        </button>
      </div>
      <div class="flex items-center gap-0.5 w-full">
      <button type="button" title="${window.t("js.paragraph.copy_paragraph_link")}" data-action="copy-link"
              class="p-1 hover:text-slate-900 hover:bg-slate-100 rounded">
        <svg ${ICON_ATTRS}>
          <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
          <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
        </svg>
      </button>
      <button type="button" title="${window.t("js.paragraph.copy_text")}" data-action="copy-text"
              class="p-1 hover:text-slate-900 hover:bg-slate-100 rounded border-l border-slate-200">
        <svg ${ICON_ATTRS}>
          <rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>
          <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>
        </svg>
      </button>
      <button type="button" title="${window.t("js.paragraph.research_paragraph")}" data-action="research"
              class="p-1 hover:text-slate-900 hover:bg-slate-100 rounded border-l border-slate-200">
        <svg ${ICON_ATTRS}>
          <path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.582a.5.5 0 0 1 0 .962L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/>
          <path d="M20 3v4"/>
          <path d="M22 5h-4"/>
          <path d="M4 17v2"/>
          <path d="M5 18H3"/>
        </svg>
      </button>
      <button type="button" title="${window.t("js.paragraph.comment_create")}" data-action="comment"
              class="p-1 hover:text-slate-900 hover:bg-slate-100 rounded border-l border-slate-200">
        <svg ${ICON_ATTRS}>
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
        </svg>
      </button>
      <button type="button" title="${window.t("js.paragraph.task_at_anchor")}" data-action="task"
              class="p-1 hover:text-slate-900 hover:bg-slate-100 rounded border-l border-slate-200">
        <svg ${ICON_ATTRS}>
          <path d="M21 10.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>
          <path d="m9 11 3 3L22 4"/>
        </svg>
      </button>
      <span class="mark-mode-badge text-[10px] font-medium text-amber-800 bg-amber-100 rounded px-1 py-0.5 self-center ml-0.5" hidden>${window.t("js.paragraph.highlight_badge")}</span>
      <button type="button" title="${window.t("js.paragraph.copy_highlight_link")}" data-action="copy-mark-link"
              hidden
              class="copy-mark-btn p-1 hover:text-slate-900 hover:bg-slate-100 rounded border-l border-slate-200 flex items-center gap-0.5">
        <svg ${ICON_ATTRS}>
          <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
          <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
          <circle cx="18" cy="6" r="2" fill="currentColor"/>
        </svg>
        <span class="mark-backlinks-count text-[10px] tabular-nums text-slate-500"></span>
      </button>
      <button type="button" title="${window.t("js.paragraph.tags_at_highlight")}" data-action="tag-mark"
              hidden
              class="tag-mark-btn p-1 hover:text-slate-900 hover:bg-slate-100 rounded border-l border-slate-200">
        <svg ${ICON_ATTRS}>
          <path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/>
          <circle cx="7.5" cy="7.5" r=".5" fill="currentColor"/>
        </svg>
      </button>
      </div>
    `

    // #365 Phase 4 (Hans, 2026-05-28): nach jedem Action-Click die Bar
    // schliessen (auf Right-Click-Trigger erwartet der User klar:
    // Aktion ausloesen, Menue weg).
    const closeAfter = () => {
      bar.hidden = true
      if (window.__paraActionsActiveBar === bar) window.__paraActionsActiveBar = null
    }
    bar.querySelector('[data-action="copy-link"]').addEventListener("click", e => {
      e.preventDefault(); this.handleCopyLink(block); closeAfter()
    })
    bar.querySelector('[data-action="copy-text"]').addEventListener("click", e => {
      e.preventDefault(); this.handleCopyText(block); closeAfter()
    })
    bar.querySelector('[data-action="research"]').addEventListener("click", e => {
      e.preventDefault(); this.handleResearch(block, e.currentTarget); closeAfter()
    })
    bar.querySelector('[data-action="comment"]').addEventListener("click", e => {
      e.preventDefault(); this.handleComment(block); closeAfter()
    })
    // #467: Aufgabe an diesem Anker erzeugen. Wenn ein Highlight rechts-
    // geklickt wurde, dessen Anker (bar.dataset.markId), sonst der Block.
    bar.querySelector('[data-action="task"]').addEventListener("click", e => {
      e.preventDefault(); this.handleCreateTask(block, bar.dataset.markId); closeAfter()
    })
    // #387 A.4 (Hans, 2026-05-28): Copy-Mark-Link → kopiere
    // `[[^<anchor>]]` in die Zwischenablage.
    bar.querySelector('[data-action="copy-mark-link"]').addEventListener("click", async e => {
      e.preventDefault()
      const markId = bar.dataset.markId
      if (!markId) { closeAfter(); return }
      try {
        await navigator.clipboard.writeText(`[[^${markId}]]`)
        this.toast(window.t("js.paragraph.highlight_link_copied"))
      } catch (err) {
        console.warn("clipboard failed:", err)
      }
      closeAfter()
    })
    // #387 Phase 2 (Hans, 2026-05-30): Tag-Editor fuer Highlight.
    // Klick auf Tag-Icon oeffnet kleinen Editor mit Chips + Input.
    bar.querySelector('[data-action="tag-mark"]').addEventListener("click", e => {
      e.preventDefault()
      const markId = bar.dataset.markId
      if (!markId) { closeAfter(); return }
      const x = parseInt(bar.style.left, 10) || 100
      const y = parseInt(bar.style.top, 10)  || 100
      closeAfter()
      this.openHighlightTagEditor(markId, x, y)
    })
    bar.querySelectorAll('[data-action="color"]').forEach(btn => {
      btn.addEventListener("click", e => {
        e.preventDefault()
        // #387 (Hans, 2026-05-28): Beim Entfernen der Farbe gehen
        // bestehende Anker mit weg → externe Links zerbrechen. Hans
        // moechte hier bewusst noch einmal bestaetigen.
        if (btn.dataset.color === "keine") {
          if (!confirm(window.t("js.paragraph.highlight_remove_confirm"))) {
            return
          }
        }
        // #475: Wurde per Rechtsklick eine bestehende Mark getroffen,
        // ueber deren Anker um-/entfaerben (sonst trifft block-N in
        // Antworten den falschen Absatz).
        this.handleColor(block, btn.dataset.color, bar.dataset.markId || null)
        closeAfter()
      })
    })

    // #452 (Hans, 2026-06-01): Im Highlight-Filter-Modus ist der „Block"
    // genau eine extrahierte Mark — Absatz-Aktionen (Farbe/Absatz-Link/
    // Text/Recherche/Kommentar) ergeben hier keinen Sinn und haetten
    // keinen Block-Anker. Wir entfernen sie; uebrig bleiben die Mark-
    // Aktionen (Tags, Highlight-Link), die ueber mark.id laufen und vom
    // contextmenu-Handler automatisch eingeblendet werden.
    if (block.classList.contains("hl-filter-block")) {
      const colorRow = bar.querySelector('[data-action="color"]')?.closest("div")
      if (colorRow) colorRow.remove()
      bar.querySelectorAll('[data-action="copy-link"], [data-action="copy-text"], [data-action="research"], [data-action="comment"]')
         .forEach(b => b.remove())
    }

    // #480 Inc.3 (Hans, 2026-06-03): Auf einer Task-Description sind Link/
    // Kommentar/Aufgabe jetzt verfuegbar (task-seitige Anker-Endpunkte +
    // TaskAnchor-Resolver). Weiterhin NICHT dabei: Recherche (haengt am
    // KI-only ParagraphResearchJob) und die Mark-Aktionen (Highlight-Link/
    // -Tags, knowledge-spezifische Endpunkte).
    if (this._isTaskSurface) {
      bar.querySelectorAll('[data-action="research"], [data-action="copy-mark-link"], [data-action="tag-mark"]')
         .forEach(b => b.remove())
    }

    // Bar wird an document.body angehaengt statt an den Block, damit
    // sie nicht von overflow:hidden / clip-Containern abgeschnitten
    // wird und position:fixed sauber auf Viewport-Koordinaten zielt.
    document.body.appendChild(bar)
    // #387/#232 Folgefix: Bar-Referenz am Block ablegen (JS-Property, kein
    // Attribut → ueberlebt den Morph), damit redecorateAfterMorph() die
    // vom Morph aus dem body entfernte Bar wieder anhaengen kann.
    block._paraBar = bar
    // #615/#616: Rueckreferenz fuer den Orphan-Sweep — die Karten-Suche
    // ersetzt Block-Nodes per innerHTML; deren Bars blieben sonst als
    // Leichen im body haengen.
    bar._ownerBlock = block

    // #365 Phase 4 (Hans, 2026-05-28): Rechtsklick + Long-Press
    // oeffnen die Bar an der Pointer-Position. Hover/Hot-Zone-Logic
    // ist weg.
    const showBarAt = (clientX, clientY) => {
      if (this._hasSelectionInBlock(block)) return
      // Globalen Single-Bar-Wechsel beibehalten — wenn eine andere
      // Bar offen ist, schliessen.
      if (window.__paraActionsActiveBar && window.__paraActionsActiveBar !== bar) {
        window.__paraActionsActiveBar.hidden = true
      }
      // #520 (Hans, 2026-06-05): den Quell-Absatz markiert lassen, solange
      // das Menü offen ist — sonst geht beim Rübergehen aufs Menü die
      // :hover-Kennzeichnung verloren und man weiß nicht mehr, worauf sich
      // das Menü bezieht.
      if (window.__paraActiveBlock && window.__paraActiveBlock !== block) {
        window.__paraActiveBlock.classList.remove("para-active")
      }
      block.classList.add("para-active")
      window.__paraActiveBlock = block
      bar.hidden = false
      // Position erst NACH unhide messen koennen (offsetWidth).
      const w = bar.offsetWidth || 160
      const h = bar.offsetHeight || 80
      // Halte die Bar im Viewport.
      const maxX = window.innerWidth  - w - 8
      const maxY = window.innerHeight - h - 8
      bar.style.left = `${Math.max(8, Math.min(clientX, maxX))}px`
      bar.style.top  = `${Math.max(8, Math.min(clientY, maxY))}px`
      window.__paraActionsActiveBar = bar
    }
    const hideBar = () => {
      bar.hidden = true
      block.classList.remove("para-active")   // #520
      if (window.__paraActiveBlock === block) window.__paraActiveBlock = null
      if (window.__paraActionsActiveBar === bar) window.__paraActionsActiveBar = null
    }

    // #387 A.4 / #654 (Hans): Liegt das Klick-/Touch-Ziel in einer
    // `<mark id>`, Anker-ID am Bar merken und die Highlight-Aktionen
    // (Wikilink kopieren, Tags) einblenden — vorher kannte nur der
    // Rechtsklick-Pfad diese Erkennung, Long-Press (mobil) nicht.
    const applyMarkContext = (targetEl, x = null, y = null) => {
      // #654 v2 (Hans, Desktop): Klicks in den Zeilen-ZWISCHENRÄUMEN eines
      // mehrzeiligen Highlights treffen das <p>, nicht die <mark> — das
      // Menü erschien dann im Block-Modus. Geometrischer Fallback: liegt
      // der Klickpunkt (±4px vertikal) in einem Zeilen-Fragment einer
      // Mark des Blocks, zählt das als Mark-Treffer.
      const markAtPoint = () => {
        if (x == null || y == null) return null
        for (const m of block.querySelectorAll("mark[id]")) {
          for (const r of m.getClientRects()) {
            if (x >= r.left && x <= r.right && y >= r.top - 4 && y <= r.bottom + 4) return m
          }
        }
        return null
      }
      const mark = (targetEl?.closest && targetEl.closest("mark[id]")) || markAtPoint()
      const copyBtn = bar.querySelector('.copy-mark-btn')
      const tagBtn  = bar.querySelector('.tag-mark-btn')
      const countSpan = bar.querySelector('.mark-backlinks-count')
      const badge = bar.querySelector('.mark-mode-badge')
      if (mark && copyBtn) {
        bar.dataset.markId = mark.id
        copyBtn.hidden = false
        if (tagBtn) tagBtn.hidden = false
        if (badge) badge.hidden = false
        // #387 Phase B: Backlink-Counter lazy laden; bei 0 leeren.
        if (countSpan) {
          countSpan.textContent = ""
          fetch(`/highlights/${mark.id}/backlinks_count`, {
            headers: { "Accept": "application/json" }
          }).then(r => r.ok ? r.json() : Promise.reject())
            .then(data => {
              if (bar.dataset.markId === mark.id && data.count > 0) {
                countSpan.textContent = data.count
              }
            }).catch(() => {})
        }
      } else if (copyBtn) {
        delete bar.dataset.markId
        copyBtn.hidden = true
        if (tagBtn) tagBtn.hidden = true
        if (badge) badge.hidden = true
        if (countSpan) countSpan.textContent = ""
      }
    }

    block.addEventListener("contextmenu", (e) => {
      // Wenn Hans bewusst das Browser-Menue will (z.B. auf einem
      // Link), nicht abfangen.
      if (e.target.closest && e.target.closest("a, button")) return
      e.preventDefault()
      // #520 (Hans, 2026-06-06): Bei verschachtelten Listen (li in li) hat
      // JEDER Eltern-Listenpunkt ebenfalls einen contextmenu-Listener. Ohne
      // stopPropagation lief der Event bis zum AEUSSERSTEN li hoch, dessen
      // Handler zuletzt feuerte und gewann → markiert/gehighlightet wurde
      // die hoechste Ebene statt der angeklickten. stopPropagation laesst nur
      // den innersten (= angeklickten) Block reagieren.
      e.stopPropagation()
      // #387 A.4 / #654: Mark-Kontext (geteilt mit dem Long-Press-Pfad).
      applyMarkContext(e.target, e.clientX, e.clientY)
      showBarAt(e.clientX, e.clientY)
    })

    // Long-Press fuer Touch-Geraete (Mobile-Pendant zu Right-Click).
    // 500ms Hold ohne grosse Bewegung → Bar oeffnen an Touch-Position.
    let touchTimer = null
    let touchStart = null
    block.addEventListener("touchstart", (e) => {
      const t = e.touches[0]
      if (!t) return
      // #520: wie beim contextmenu — nur der innerste Listenpunkt soll den
      // Long-Press-Timer starten, nicht zusaetzlich alle Eltern-Ebenen.
      e.stopPropagation()
      touchStart = { x: t.clientX, y: t.clientY }
      const touchTarget = e.target   // #654: Mark unterm Finger erkennen
      touchTimer = setTimeout(() => {
        applyMarkContext(touchTarget, touchStart.x, touchStart.y)
        showBarAt(touchStart.x, touchStart.y)
        touchTimer = null
      }, 500)
    }, { passive: true })
    const cancelTouch = (e) => {
      if (touchTimer) { clearTimeout(touchTimer); touchTimer = null }
      if (e?.touches?.[0] && touchStart) {
        const dx = Math.abs(e.touches[0].clientX - touchStart.x)
        const dy = Math.abs(e.touches[0].clientY - touchStart.y)
        if (dx < 10 && dy < 10) return
      }
      touchStart = null
    }
    block.addEventListener("touchmove",   cancelTouch, { passive: true })
    block.addEventListener("touchend",    cancelTouch)
    block.addEventListener("touchcancel", cancelTouch)

    // Bar schliessen bei Click ausserhalb / Escape.
    if (!this._globalCloseInstalled) {
      this._globalCloseInstalled = true
      const clearActiveBlock = () => {   // #520
        window.__paraActiveBlock?.classList.remove("para-active")
        window.__paraActiveBlock = null
      }
      this._onGlobalClick = (e) => {
        const active = window.__paraActionsActiveBar
        if (!active || active.hidden) return
        if (e.target.closest && e.target.closest(".para-actions") === active) return
        active.hidden = true
        window.__paraActionsActiveBar = null
        clearActiveBlock()
      }
      this._onGlobalEsc = (e) => {
        if (e.key !== "Escape") return
        const active = window.__paraActionsActiveBar
        if (!active || active.hidden) return
        active.hidden = true
        window.__paraActionsActiveBar = null
        clearActiveBlock()
      }
      document.addEventListener("mousedown", this._onGlobalClick)
      document.addEventListener("keydown",   this._onGlobalEsc)
    }
    // Bars bei Disconnect aufraeumen.
    this._bars ||= []
    this._bars.push(bar)
    // Selektion zum Wegschalten der Bar — selectionchange feuert auf
    // dem document; wir checken pro Block, ob die Selection drinliegt.
    // #365 Phase 3 (Hans, 2026-05-25): bei aktiver Selection ZUSAETZLICH
    // einen kleinen Selection-Highlight-Bar mit 5 Farben oben anzeigen.
    // Klick → POST wrap_highlight mit anchor + selected_text + color.
    if (!this._selectionListenerInstalled) {
      this._selectionListenerInstalled = true
      this._onSelectionChange = () => {
        // #365 Phase 4 (Hans, 2026-05-28): Bars haengen jetzt am
        // document.body, nicht mehr am Block. Wenn der User Text
        // selektiert, schliessen wir die aktive Right-Click-Bar
        // (sie hat eh keinen Bezug zur Selektion). Selection-Bar
        // erscheint separat via _refreshSelectionHighlightBar.
        if (window.__paraActionsActiveBar && !window.__paraActionsActiveBar.hidden) {
          const sel = window.getSelection?.()
          if (sel && !sel.isCollapsed) {
            window.__paraActionsActiveBar.hidden = true
            window.__paraActionsActiveBar = null
          }
        }
        this._refreshSelectionHighlightBar()
      }
      document.addEventListener("selectionchange", this._onSelectionChange)
    }
  }

  // #232/#387 Folgefix: nach einem Turbo-Morph die client-seitigen
  // Augmentierungen wiederherstellen, OHNE Listener doppelt zu wiren.
  // Erhaltene Bloecke (im WeakSet) haben ihre contextmenu/touch-Listener
  // noch — sie verloren nur die Klassen und ihre Bar wurde aus dem body
  // entfernt. Neue Bloecke (Inhalt hat sich geaendert) voll augmentieren.
  // #615/#616: auch von reply_search aufgerufen — die Karten-Suche
  // ersetzt Block-Nodes per innerHTML (Restore/Highlights); die neuen
  // Nodes brauchen volle Augmentierung, die alten Bars den Sweep.
  redecorateAfterMorph() {
    document.querySelectorAll(".para-actions").forEach(bar => {
      if (bar._ownerBlock && !bar._ownerBlock.isConnected) bar.remove()
    })
    const article = this.element.querySelector(".markdown-body")
    if (!article) return
    article.querySelectorAll("p[id], li[id], blockquote[id], h1[id], h2[id], h3[id], h4[id], h5[id], h6[id], .hl-filter-block").forEach(block => {
      if (this._augmentedBlocks.has(block)) {
        block.classList.add("para-anchorable", "relative", "group/block")
        const bar = block._paraBar
        if (bar && !bar.isConnected) document.body.appendChild(bar)
      } else {
        this.augment(block)
      }
    })
  }

  disconnect() {
    if (this._onTurboRender) {
      document.removeEventListener("turbo:render", this._onTurboRender)
      this._onTurboRender = null
    }
    if (this._onSelectionChange) {
      document.removeEventListener("selectionchange", this._onSelectionChange)
      this._onSelectionChange = null
      this._selectionListenerInstalled = false
    }
    if (this._onGlobalClick) {
      document.removeEventListener("mousedown", this._onGlobalClick)
      this._onGlobalClick = null
    }
    if (this._onGlobalEsc) {
      document.removeEventListener("keydown", this._onGlobalEsc)
      this._onGlobalEsc = null
    }
    this._globalCloseInstalled = false
    if (this._bars) {
      this._bars.forEach(b => b.remove())
      this._bars = null
    }
    this._removeSelectionBar()
  }

  _hasSelectionInBlock(block) {
    const sel = window.getSelection?.()
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return false
    const range = sel.getRangeAt(0)
    return block.contains(range.startContainer) || block.contains(range.endContainer)
  }

  // #365 Phase 3 (Hans, 2026-05-25): Selection-Highlight-Bar — kleiner
  // Floating-Bar mit 5 Farben, der bei aktiver Text-Selektion innerhalb
  // eines Blocks ueber der Selektion erscheint. Klick wraps die
  // Selektion in `==color|text==` (persistent in der Body-Datei).
  _refreshSelectionHighlightBar() {
    const sel = window.getSelection?.()
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) {
      this._removeSelectionBar()
      return
    }
    const range = sel.getRangeAt(0)
    // Welcher anker-faehige Block enthaelt die Selection?
    let block = range.commonAncestorContainer
    if (block.nodeType === 3) block = block.parentElement
    block = block.closest?.(".para-anchorable")
    if (!block || !this.element.contains(block)) {
      this._removeSelectionBar()
      return
    }
    const rect = range.getBoundingClientRect()
    if (rect.width < 2 || rect.height < 2) {
      this._removeSelectionBar()
      return
    }
    const text = sel.toString()
    if (!text) { this._removeSelectionBar(); return }

    if (!this._selectionBar) {
      const bar = document.createElement("div")
      // #520 (Hans, 2026-06-06): zweizeilig wie das Block-Menü — Farben oben,
      // Befehle unten, beide linksbündig.
      bar.className = "selection-highlight-bar fixed z-40 bg-white border border-slate-200 rounded shadow-md flex flex-col items-stretch"
      const colorRow = document.createElement("div")
      colorRow.className = "flex items-center gap-0.5 px-0.5 py-0.5 border-b border-slate-200 justify-start"
      const cmdRow = document.createElement("div")
      cmdRow.className = "flex items-center gap-0.5 px-0.5 py-0.5 justify-start"
      const mkBtn = (color, cls) => {
        const b = document.createElement("button")
        b.type = "button"
        b.className = `w-5 h-5 rounded border border-slate-200 ${cls}`
        b.title = window.t("js.paragraph.highlight_selection", { color })
        b.addEventListener("mousedown", e => e.preventDefault())  // verhindert Selection-Loss
        b.addEventListener("click", e => {
          e.preventDefault()
          // #387 Phase A-Fix4 (Hans, 2026-05-28): NICHT den closure-
          // captured `text` aus dem initialen Bar-Render-Lauf nehmen
          // — der ist stale, sobald der User die Selektion nach dem
          // ersten Erscheinen des Bars erweitert/verkleinert. Frisch
          // aus der aktiven Selection lesen.
          const liveSel  = window.getSelection?.()
          const liveText = liveSel?.toString?.() || text
          if (color === "keine" &&
              !confirm(window.t("js.paragraph.highlight_remove_confirm"))) {
            return
          }
          this._applySelectionHighlight(block, liveText, color)
        })
        return b
      }
      colorRow.appendChild(mkBtn("gelb",  "bg-amber-200 hover:bg-amber-300"))
      colorRow.appendChild(mkBtn("rot",   "bg-rose-200 hover:bg-rose-300"))
      colorRow.appendChild(mkBtn("gruen", "bg-emerald-200 hover:bg-emerald-300"))
      colorRow.appendChild(mkBtn("blau",  "bg-sky-200 hover:bg-sky-300"))
      colorRow.appendChild(mkBtn("lila",  "bg-violet-200 hover:bg-violet-300"))
      // #365-follow (Hans, 2026-05-25 21:36): no-color-Button entfernt
      // existierende Wraps um die Selektion.
      const noColor = mkBtn("keine", "bg-white hover:bg-slate-100 text-slate-500")
      noColor.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 m-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg>`
      noColor.title = window.t("js.paragraph.highlight_remove")
      colorRow.appendChild(noColor)

      // #469 (Hans, 2026-06-02): das Selektions-Menue um die uebrigen
      // Befehle erweitern (Link / Kommentar / Aufgabe). „Praezise"
      // (Hans-Spec): erst die Selektion highlighten (-> frischer 8-Hex-
      // Anker), dann Link/Kommentar/Aufgabe genau an diesen Anker haengen
      // — nicht an den umgebenden Absatz. Default-Highlight-Farbe gelb;
      // Hans kann sie ueber die Farbknoepfe nachfaerben (Anker bleibt).
      const ICONS = {
        link: '<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 m-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>',
        comment: '<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 m-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>',
        task: '<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 m-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/><path d="m9 11 3 3L22 4"/></svg>',
        copy: '<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 m-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>',
        research: '<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 m-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.582a.5.5 0 0 1 0 .962L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/><path d="M20 3v4"/><path d="M22 5h-4"/><path d="M4 17v2"/><path d="M5 18H3"/></svg>',
        person: '<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 m-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>'
      }
      const mkCmd = (title, svg, onClick) => {
        const b = document.createElement("button")
        b.type = "button"
        b.className = "w-5 h-5 rounded border border-slate-200 text-slate-600 hover:bg-slate-100 flex items-center justify-center"
        b.title = title
        b.innerHTML = svg
        b.addEventListener("mousedown", e => e.preventDefault())  // Selection halten
        b.addEventListener("click", e => { e.preventDefault(); onClick() })
        return b
      }
      // #480/#520: Befehle in der GLEICHEN Reihenfolge wie das Block-Menü:
      // Link · Text · Recherche · Kommentar · Aufgabe. Jeder ankert zuerst die
      // Selektion (frischer 8-Hex-Highlight-Anker) und hängt sich genau dort an.
      // #655 (Hans): Auswahl als Personen-Wikilink auszeichnen ([[@Name]]).
      cmdRow.appendChild(mkCmd(window.t("js.paragraph.link_as_person"), ICONS.person, async () => {
        const liveText = window.getSelection?.()?.toString?.() || text
        await this._applyPersonWrap(block, liveText)
      }))
      cmdRow.appendChild(mkCmd(window.t("js.paragraph.copy_selection_link"), ICONS.link, async () => {
        const liveText = window.getSelection?.()?.toString?.() || ""
        this._removeSelectionBar()
        const anchor = await this._anchorSelection(block, liveText)
        if (!anchor) return
        await this.handleCopyLink(block, anchor, liveText)
        await this._reloadAfterBodyChange(block)
      }))
      // #520: Copy verdrängt das Browser-Menü → hier; kopiert die Live-Selektion.
      cmdRow.appendChild(mkCmd(window.t("js.paragraph.copy_selection_text"), ICONS.copy, async () => {
        const liveText = window.getSelection?.()?.toString?.() || ""
        this._removeSelectionBar()
        if (!liveText) return
        try {
          await navigator.clipboard.writeText(liveText)
          this.toast(window.t("js.paragraph.selection_text_copied"))
        } catch (err) {
          console.warn("clipboard failed:", err)
        }
      }))
      // #520: Recherche zur Auswahl → Recherche-Aufgabe am Highlight-Anker.
      cmdRow.appendChild(mkCmd(window.t("js.paragraph.research_selection"), ICONS.research, async () => {
        const liveText = window.getSelection?.()?.toString?.() || ""
        this._removeSelectionBar()
        const anchor = await this._anchorSelection(block, liveText)
        if (!anchor) return
        await this._createResearchTask(anchor, liveText)
        await this._reloadAfterBodyChange(block)
      }))
      cmdRow.appendChild(mkCmd(window.t("js.paragraph.comment_selection"), ICONS.comment, async () => {
        const liveText = window.getSelection?.()?.toString?.() || ""
        this._removeSelectionBar()
        const anchor = await this._anchorSelection(block, liveText)
        if (!anchor) return
        // handleComment laedt die Quell-Card selbst neu (zeigt Highlight
        // + frischen Backlink-Zaehler) und oeffnet die Kommentar-Card.
        await this.handleComment(block, anchor)
      }))
      cmdRow.appendChild(mkCmd(window.t("js.paragraph.task_selection"), ICONS.task, async () => {
        const liveText = window.getSelection?.()?.toString?.() || ""
        this._removeSelectionBar()
        const anchor = await this._anchorSelection(block, liveText)
        if (!anchor) return
        await this.handleCreateTask(block, anchor, liveText)
        await this._reloadAfterBodyChange(block)
      }))

      bar.appendChild(colorRow)
      bar.appendChild(cmdRow)
      document.body.appendChild(bar)
      this._selectionBar = bar
    }
    // Positionieren: ueber der Selektion zentriert. #520: jetzt zweizeilig,
    // also Höhe dynamisch messen statt fixem -36 (sonst überlappt die Bar
    // die Selektion). Im Viewport halten.
    const h = this._selectionBar.offsetHeight || 64
    const w = this._selectionBar.offsetWidth  || 160
    const top  = Math.max(8, rect.top - h - 6)
    const left = Math.max(8, Math.min(rect.left + rect.width / 2 - w / 2, window.innerWidth - w - 8))
    this._selectionBar.style.top  = `${top}px`
    this._selectionBar.style.left = `${left}px`
  }

  _removeSelectionBar() {
    if (this._selectionBar) {
      this._selectionBar.remove()
      this._selectionBar = null
    }
  }

  async _applySelectionHighlight(block, selectedText, color) {
    const anchor = block.id
    if (!anchor) return
    // #365 (Hans, 2026-05-28): Leading/trailing whitespace aus der
    // Selektion entfernen — sonst entsteht ein `==color| Text==` mit
    // Leerzeichen am Anfang, das beim Re-Render im HTML hinterm
    // `<mark>`-Tag sichtbar bleibt.
    const cleanText = selectedText.replace(/^\s+|\s+$/g, "")
    if (!cleanText) return
    const fd = new FormData()
    fd.append("anchor",        anchor)
    fd.append("color",         color)
    fd.append("selected_text", cleanText)
    const res = await fetch(`${this._base}/wrap_highlight`, {
      method: "POST",
      headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content, "Accept": "application/json" },
      body: fd
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      this.toast(err.error || window.t("js.paragraph.highlight_failed"))
      return
    }
    this._removeSelectionBar()
    window.getSelection()?.removeAllRanges()
    // #520 (Hans, 2026-06-06): In ANTWORTEN gibt es keine Stack-Card mit
    // dieser uuid — refreshCard(uuidValue) lief dort ins Leere, der frische
    // Highlight erschien nie („keine Highlights machen", v.a. in Entwürfen).
    // Gleiche reply-bewusste Logik wie handleColor: Stack-Card refreshen,
    // sonst das umgebende Replies-turbo-frame neu laden.
    const stackCard = document.querySelector(`.stack-card[data-uuid="${this.uuidValue}"]`)
    if (stackCard) {
      // #365 (Hans, 2026-05-28): Scroll-Position der Card retten + nach
      // refreshCard wiederherstellen, damit Hans nicht nach oben springt.
      const card = block.closest(".stack-card")
      const scroller = card?.querySelector(".overflow-y-auto")
      const savedTop = scroller?.scrollTop ?? null
      const stackCtl = this.findBladeStackController()
      if (stackCtl) await stackCtl.refreshCard(this.uuidValue)
      if (savedTop != null) {
        const newCard = document.querySelector(`.stack-card[data-uuid="${this.uuidValue}"]`)
        const newScroller = newCard?.querySelector(".overflow-y-auto")
        if (newScroller) newScroller.scrollTop = savedTop
      }
    } else {
      block.closest("turbo-frame")?.reload?.()
    }
  }

  // #655 (Hans): Auswahl als Personen-Wikilink ([[@Name]]) auszeichnen.
  // Bestehende Personen findet der Resolver per Titel/Alias; fehlende
  // rendern als „missing" und lassen sich über den Entitäten-Import
  // (Researcher) anlegen. Refresh wie beim Selektions-Highlight.
  async _applyPersonWrap(block, selectedText) {
    const anchor = block.id
    if (!anchor) return
    const cleanText = (selectedText || "").replace(/^\s+|\s+$/g, "")
    if (!cleanText) return
    const fd = new FormData()
    fd.append("anchor",        anchor)
    fd.append("selected_text", cleanText)
    const res = await fetch(`${this._base}/wrap_person`, {
      method: "POST",
      headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content, "Accept": "application/json" },
      body: fd
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      this.toast(err.error || window.t("js.paragraph.person_link_failed"))
      return
    }
    this._removeSelectionBar()
    window.getSelection()?.removeAllRanges()
    this.toast(window.t("js.paragraph.person_linked", { name: cleanText }))
    const stackCard = document.querySelector(`.stack-card[data-uuid="${this.uuidValue}"]`)
    if (stackCard) {
      const card = block.closest(".stack-card")
      const scroller = card?.querySelector(".overflow-y-auto")
      const savedTop = scroller?.scrollTop ?? null
      const stackCtl = this.findBladeStackController()
      if (stackCtl) await stackCtl.refreshCard(this.uuidValue)
      if (savedTop != null) {
        const newCard = document.querySelector(`.stack-card[data-uuid="${this.uuidValue}"]`)
        const newScroller = newCard?.querySelector(".overflow-y-auto")
        if (newScroller) newScroller.scrollTop = savedTop
      }
    } else {
      block.closest("turbo-frame")?.reload?.()
    }
  }

  // #469 (Hans, 2026-06-02): Selektion praezise ankern. Wrappt den
  // markierten Text in ein (default-gelbes) Highlight und liefert den
  // frisch gesetzten 8-Hex-Anker zurueck — Basis fuer praezisen
  // Link/Kommentar/Aufgabe aus dem Selektions-Menue. KEIN Card-Refresh
  // hier (der Caller laedt danach neu bzw. erledigt das in seinem Flow).
  async _anchorSelection(block, selectedText, color = "gelb") {
    const cleanText = (selectedText || "").replace(/^\s+|\s+$/g, "")
    if (!cleanText || !block?.id) return null
    const fd = new FormData()
    fd.append("anchor",        block.id)
    fd.append("color",         color)
    fd.append("selected_text", cleanText)
    const res = await fetch(`${this._base}/wrap_highlight`, {
      method: "POST",
      headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content, "Accept": "application/json" },
      body: fd
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      this.toast(err.error || window.t("js.paragraph.anchor_failed"))
      return null
    }
    const data = await res.json().catch(() => ({}))
    return data.anchor || null
  }

  // #469: Card (oder Antwort-Frame) nach einer Body-Aenderung neu laden,
  // damit das frische Highlight sichtbar wird. Scroll-Position retten.
  async _reloadAfterBodyChange(block) {
    const stackCard = document.querySelector(`.stack-card[data-uuid="${this.uuidValue}"]`)
    if (stackCard) {
      const scroller = stackCard.querySelector(".overflow-y-auto")
      const savedTop = scroller?.scrollTop ?? null
      const stackCtl = this.findBladeStackController()
      if (stackCtl) await stackCtl.refreshCard(this.uuidValue)
      if (savedTop != null) {
        const ns = document.querySelector(`.stack-card[data-uuid="${this.uuidValue}"] .overflow-y-auto`)
        if (ns) ns.scrollTop = savedTop
      }
    } else {
      block?.closest("turbo-frame")?.reload?.()
    }
  }

  // Klick auf den dauerhaften Counter-Indicator am Block-Ende (vom
  // Server gerendert via inject_block_ids → backlink_indicator_html).
  // Öffnet einen kleinen Popover direkt unter dem Icon. Popover-Logik
  // (Fetch, Rendering, Outside-Click-Close) lebt in lib/backlinks_popover.
  showBacklinks(event) {
    event.preventDefault()
    event.stopPropagation()
    const link = event.currentTarget
    const anchor = link.dataset.anchor
    if (!anchor) return
    this._popover ||= new BacklinksPopover({
      uuid: this.uuidValue,
      application: this.application,
      onItemClick: ({ navUuid, scrollTo }) => {
        // #312/#501: schon offene Card fokussieren statt eine neue anzulegen;
        // nur wenn neu, am Stack-Ende anfuegen. Bei einer Antwort-Quelle ist
        // navUuid die ganze Aufgabe/KI (task:ID bzw. KI-UUID) und scrollTo die
        // Antwort (reply_<uuid>) — dorthin wird gescrollt.
        const stackCtl = this.findBladeStackController()
        if (!stackCtl || !navUuid) return
        const existing = stackCtl.cardForUuid(navUuid)
        if (existing) {
          existing.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" })
          stackCtl.setActiveCard(existing)
          if (scrollTo) stackCtl.scrollToAnchorInCard(existing, scrollTo)
        } else {
          stackCtl.appendCard(navUuid).then(() => {
            stackCtl.pushTrailState()
            if (scrollTo) {
              const fresh = stackCtl.cardForUuid(navUuid)
              if (fresh) stackCtl.scrollToAnchorInCard(fresh, scrollTo)
            }
          })
        }
      }
    })
    this._popover.open(link, anchor)
  }

  // #309 (Hans): URL-Kopie -> Wikilink-Kopie. Stattdessen `[[Title^anchor]]`
  // in die Zwischenablage, damit man's direkt in ein anderes KI
  // einfuegen kann (Markdown-Renderer macht daraus den getypten
  // Wikilink mit Block-Anker).
  // #469 (Hans, 2026-06-02): anchorOverride + aliasOverride erlauben den
  // praezisen Auswahl-Link (Selektions-Menue): Anker = der frische
  // Selektions-Highlight-Anker, Alias = der markierte Text.
  async handleCopyLink(block, anchorOverride = null, aliasOverride = null) {
    const anchor = anchorOverride || await this.ensureAnchor(block)
    if (!anchor) return
    const title = (this.titleValue || "").trim()
    // #664 (Hans): Titel mit wikilink-brechenden Zeichen (`| # ^ [ ]` —
    // etwa YouTube-Titel „… | Jaron Lanier") zerstören `[[Titel^anker]]`
    // (der Parser zerlegt am `|`). Dann aufs UUID-Target ausweichen; der
    // Titel kommt ggf. als Alias bzw. wird beim Rendern eh angezeigt.
    const unsafe = title && /[\[\]|#^]/.test(title)
    const uuid   = (this.uuidValue || "").trim()
    const inner  = !title            ? `^${anchor}`
                 : (unsafe && uuid)  ? `${uuid}^${anchor}`
                 :                     `${title}^${anchor}`
    // #461/#466 (Hans, 2026-06-02): Alternate-Display.
    //  - Auswahl-Link (#469): der markierte Text als Alias.
    //  - Antwort (reply): „Thread-Antwort" (Link zeigt auf den Parent).
    //  - Heading: der Heading-Text.
    // #466: Antwort -> „Thread-Antwort". KI-Parent: [[KI^anker|…]];
    // Task-Parent (kein Titel): [[^anker|…]] — der Resolver loest den
    // Anker-only-Link auf den Parent (Aufgabe) auf. Heading sonst: Text.
    let alias = (aliasOverride || "").replace(/\s+/g, " ").trim().slice(0, 120)
    if (!alias) {
      if (this.replyValue) alias = "Thread-Antwort"
      else if (/^H[1-6]$/.test(block.tagName)) alias = this._blockText(block)
    }
    const wikilink = alias ? `[[${inner}|${alias}]]` : `[[${inner}]]`
    try {
      await navigator.clipboard.writeText(wikilink)
      this.toast(aliasOverride ? window.t("js.paragraph.selection_link_copied")
                 : (alias ? window.t("js.paragraph.heading_link_copied") : window.t("js.paragraph.paragraph_link_copied")))
    } catch (err) {
      console.warn("clipboard failed:", err)
    }
  }

  // Reiner Text eines Blocks ohne die eingehaengte para-actions-Bar.
  _blockText(block) {
    const bar = block.querySelector(".para-actions")
    bar?.style.setProperty("display", "none")
    const text = block.innerText.trim()
    bar?.style.removeProperty("display")
    return text
  }

  // Reinen Absatz-Text in die Zwischenablage. Toolbar-Button selbst
  // wird vor dem Lesen kurz aus dem Block-Subtree entfernt, sonst landen
  // SVG-Texte oder Button-Labels mit im innerText.
  async handleCopyText(block) {
    const bar = block.querySelector(".para-actions")
    bar?.style.setProperty("display", "none")
    const text = block.innerText.trim()
    bar?.style.removeProperty("display")
    if (!text) return
    try {
      await navigator.clipboard.writeText(text)
      this.toast(window.t("js.paragraph.paragraph_text_copied"))
    } catch (err) {
      console.warn("clipboard failed:", err)
    }
  }

  // Öffnet ein kleines Popover unter dem Recherche-Button mit
  // optionaler Eingabe für zusätzliche Hinweise. Submit triggert
  // serverseitig einen Background-Job; das KI mit der Antwort
  // erscheint später in den Backlinks dieses Absatzes.
  async handleResearch(block, buttonEl) {
    const anchor = await this.ensureAnchor(block)
    if (!anchor) return

    document.querySelectorAll(".para-research-popover").forEach(p => p.remove())

    const pop = document.createElement("div")
    pop.className = "para-research-popover fixed z-50 bg-white border border-slate-200 rounded shadow-lg p-3 text-xs w-72"
    pop.innerHTML = `
      <div class="text-[11px] uppercase tracking-wider text-slate-500 mb-1">${window.t("js.paragraph.research_popover_title")}</div>
      <textarea data-role="hints" rows="3" placeholder="${window.t("js.paragraph.research_hints_placeholder")}" class="w-full text-xs rounded border border-slate-200 px-2 py-1 focus:outline-none focus:ring-2 focus:ring-emerald-400"></textarea>
      <div class="flex items-center justify-end gap-2 mt-2">
        <button type="button" data-role="cancel" class="text-xs px-2 py-1 rounded border border-slate-200 hover:bg-slate-50">${window.t("js.paragraph.cancel")}</button>
        <button type="button" data-role="submit" class="text-xs px-2 py-1 rounded bg-emerald-600 text-white hover:bg-emerald-700 cursor-pointer">${window.t("js.paragraph.create_task")}</button>
      </div>
    `

    const rect = buttonEl.getBoundingClientRect()
    pop.style.top  = `${rect.bottom + 4}px`
    pop.style.left = `${Math.max(8, rect.right - 288)}px`
    document.body.appendChild(pop)
    pop.querySelector('[data-role="hints"]').focus()

    const close = () => { pop.remove(); document.removeEventListener("click", outside, true) }
    const outside = (e) => { if (!pop.contains(e.target) && e.target !== buttonEl) close() }
    setTimeout(() => document.addEventListener("click", outside, true), 0)

    pop.querySelector('[data-role="cancel"]').addEventListener("click", close)
    pop.querySelector('[data-role="submit"]').addEventListener("click", async () => {
      const hints = pop.querySelector('[data-role="hints"]').value.trim()
      const title = (this._blockText(block) || "").slice(0, 120)
      close()
      // #512 (Hans, 2026-06-04): Lupe legt jetzt eine Recherche-AUFGABE am
      // Anker an (Verweis aufs Entitäts-Recherche-Verfahren) statt einen
      // asynchronen LLM-Job — und öffnet sie sofort im Stack.
      const res = await fetch(`${this._base}/task_at`, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept":       "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: new URLSearchParams({ anchor, title, hints, research: "1" }).toString()
      })
      if (!res.ok) {
        this.toast(window.t("js.paragraph.research_task_failed"))
        return
      }
      const data = await res.json()
      if (!data.task_id) return
      const stackCtl = this.findBladeStackController()
      if (stackCtl) {
        await stackCtl.appendCard(`task:${data.task_id}`)
        stackCtl.restickify()
        stackCtl.applyHighlighting()
        stackCtl.syncUrl({ pushHistory: false })
      }
      this.toast(window.t("js.paragraph.research_task_created"))
    })
  }

  // #520 (Hans, 2026-06-06): Recherche-Aufgabe an einem (Highlight-)Anker
  // anlegen und sofort im Stack öffnen — vom Auswahl-Menü genutzt (das
  // Block-Menü hat dafür den Hinweis-Popover in handleResearch).
  async _createResearchTask(anchor, title) {
    const params = new URLSearchParams({ anchor, title: (title || "").slice(0, 120), research: "1" })
    const res = await fetch(`${this._base}/task_at`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept":       "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: params.toString()
    })
    if (!res.ok) { this.toast(window.t("js.paragraph.research_task_failed")); return }
    const data = await res.json()
    if (!data.task_id) return
    const stackCtl = this.findBladeStackController()
    if (stackCtl) {
      await stackCtl.appendCard(`task:${data.task_id}`)
      stackCtl.restickify()
      stackCtl.applyHighlighting()
      stackCtl.syncUrl({ pushHistory: false })
    }
    this.toast(window.t("js.paragraph.research_task_created"))
  }

  // #467 (Hans, 2026-06-02): Aufgabe an einem Anker erzeugen — die
  // Beschreibung traegt den Wikilink auf den Anker. markId (falls ein
  // Highlight rechts-geklickt wurde) gewinnt vor dem Block-Anker.
  async handleCreateTask(block, markId, titleOverride) {
    const anchor = markId || await this.ensureAnchor(block)
    if (!anchor) return
    // #466 (Hans, 2026-06-02): Aus einer Antwort KEINEN Titel aus dem
    // markierten Text vorbelegen — der Server setzt dann Platzhalter +
    // Thread-Antwort-Link, und wir fokussieren das Titelfeld.
    const title = this.replyValue
      ? ""
      : (titleOverride?.trim() || this._blockText(block)).slice(0, 120)
    const res = await fetch(`${this._base}/task_at`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept":       "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: new URLSearchParams({ anchor, title }).toString()
    })
    if (!res.ok) { this.toast(window.t("js.paragraph.task_failed")); return }
    const data = await res.json()
    if (!data.task_id) return
    const stackCtl = this.findBladeStackController()
    if (stackCtl) {
      await stackCtl.appendCard(`task:${data.task_id}`)
      stackCtl.restickify()
      stackCtl.applyHighlighting()
      stackCtl.syncUrl({ pushHistory: false })
      // #466: Antwort-Task ohne sinnvollen Titel -> Titelfeld der
      // frischen Card fokussieren + Platzhalter selektieren, damit Hans
      // direkt lostippt (honoriert „Titel leer lassen").
      if (data.reply) this._focusNewTaskTitle(data.task_id)
    }
    this.toast(window.t("js.paragraph.task_created"))
  }

  // #466: Titelfeld der frisch angehaengten Task-Card fokussieren. Die
  // Card kann via Turbo-Frame nachladen, daher kurz pollen.
  _focusNewTaskTitle(taskId, tries = 12) {
    const field = document.querySelector(
      `.stack-card[data-uuid="task:${taskId}"] textarea[name="task[title]"]`
    )
    if (field) {
      field.focus()
      field.select?.()
      return
    }
    if (tries > 0) setTimeout(() => this._focusNewTaskTitle(taskId, tries - 1), 80)
  }

  // #469: anchorOverride = praeziser Selektions-Anker (Selektions-Menue).
  async handleComment(block, anchorOverride = null) {
    const anchor = anchorOverride || await this.ensureAnchor(block)
    if (!anchor) return
    const res = await fetch(`${this._base}/comment_at`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept":       "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: new URLSearchParams({ anchor }).toString()
    })
    if (!res.ok) { this.toast(window.t("js.paragraph.comment_failed")); return }
    const data = await res.json()

    // Comment-Card im Stack rechts neben der aktuellen Card öffnen
    // und in den Edit-Mode versetzen. Vorher die Source-Card neu laden,
    // damit der frisch entstandene Backlink-Counter am Absatz erscheint.
    const stackCtl = this.findBladeStackController()
    if (stackCtl) {
      const anchorCard = block.closest("[data-uuid]")
      if (anchorCard) stackCtl.truncateAfter(anchorCard)
      await stackCtl.refreshCard(this.uuidValue)
      await stackCtl.appendCard(data.uuid)
      stackCtl.restickify()
      stackCtl.applyHighlighting()
      stackCtl.syncUrl({ pushHistory: false })
      // Edit-Mode der frischen Card per Frame-Swap. Kein Klick auf den
      // Edit-Link — der löst eine Turbo-Vollnavigation aus, die den
      // Stack platt macht.
      await this.openCardInEditMode(data.uuid)
    } else {
      // Fallback: Vollansicht edit
      window.location.href = `/knowledge_items/${data.uuid}/edit`
    }
  }

  // #365 Phase 3 (Hans, 2026-05-25): Klick auf Farbe in der Iconbar
  // wrappt den GANZEN Absatz im Body in `==color|text==`. Server-
  // Action wrap_highlight persistiert die Aenderung; danach laden wir
  // die Card frisch.
  // #475 (Hans, 2026-06-03): anchorOverride = die Anker-ID eines bereits
  // bestehenden Highlights (mark.id). Beim Um-/Entfaerben MUSS darueber
  // gegangen werden statt ueber block.id: in Antworten rendert der Inline-
  // Renderer mit hard_wrap, dadurch stimmt die DOM-Block-Nummer (block-N)
  // NICHT mit der quell-basierten Block-Nummer des Servers ueberein — ein
  // block-N-Recolor traefe den falschen Absatz. Der Server lokalisiert den
  // Block ueber `^anker` zuverlaessig (nummerierungs-unabhaengig).
  async handleColor(block, color, anchorOverride = null) {
    const anchor = anchorOverride || block.id  // mark-Anker, sonst block-N/^id
    if (!anchor) return
    const fd = new FormData()
    fd.append("anchor", anchor)
    fd.append("color",  color)
    const res = await fetch(`${this._base}/wrap_highlight`, {
      method: "POST",
      headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content, "Accept": "application/json" },
      body: fd
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      this.toast(err.error || window.t("js.paragraph.highlight_failed"))
      return
    }
    // #365 (Hans, 2026-05-28): Scroll-Position vor Card-Refresh sichern.
    const card = block.closest(".stack-card")
    const scroller = card?.querySelector(".overflow-y-auto")
    const savedTop = scroller?.scrollTop ?? null
    // #465/#466 (Hans, 2026-06-02): In Antworten gibt es KEINE Stack-Card
    // mit dieser uuid — stattdessen das umgebende Replies-turbo-frame neu
    // laden, damit der frische Highlight erscheint. Sonst (KI-Body) wie
    // bisher die Stack-Card refreshen.
    const stackCard = document.querySelector(`.stack-card[data-uuid="${this.uuidValue}"]`)
    if (stackCard) {
      const stackCtl = this.findBladeStackController()
      if (stackCtl) await stackCtl.refreshCard(this.uuidValue)
      if (savedTop != null) {
        const newCard = document.querySelector(`.stack-card[data-uuid="${this.uuidValue}"]`)
        const newScroller = newCard?.querySelector(".overflow-y-auto")
        if (newScroller) newScroller.scrollTop = savedTop
      }
    } else {
      block.closest("turbo-frame")?.reload?.()
    }
  }

  // Lädt /edit für eine bereits offene Card und tauscht das Detail-
  // Frame in-place gegen die Edit-Variante. Vermeidet Turbo-Vollnavi-
  // gation bzw. das Risiko, dass der Stack zerlegt wird.
  async openCardInEditMode(uuid) {
    const res = await fetch(`/knowledge_items/${uuid}/edit?in_stack=1`, {
      headers: { "Accept": "text/html" }
    })
    if (!res.ok) return
    const html = await res.text()
    const doc  = new DOMParser().parseFromString(html, "text/html")
    const fresh = doc.querySelector(`turbo-frame#knowledge_detail_${uuid}`)
    const old   = document.querySelector(`turbo-frame#knowledge_detail_${uuid}`)
    if (fresh && old) {
      old.replaceWith(fresh)
      // Rails f.text_area :content rendert name="knowledge_item[content]".
      fresh.querySelector('textarea[name*="content"]')?.focus()
    }
  }

  // Sorgt dafür, dass der Block einen stabilen Anker hat. Wenn die
  // ID schon stable ist (kein block-N), gibt sie zurück. Sonst Server
  // anrufen, der eine ID anhängt.
  async ensureAnchor(block) {
    if (!/^block-\d+$/.test(block.id)) return block.id
    const res = await fetch(`${this._base}/ensure_anchor`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept":       "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: new URLSearchParams({ anchor: block.id }).toString()
    })
    if (!res.ok) { this.toast(window.t("js.paragraph.anchor_failed")); return null }
    const data = await res.json()
    block.id = data.anchor
    return data.anchor
  }

  findBladeStackController() {
    const stackEl = document.querySelector("[data-controller~=blade-stack]")
    if (!stackEl) return null
    const app = window.Stimulus
    if (!app) return null
    return app.getControllerForElementAndIdentifier(stackEl, "blade-stack")
  }

  // #387 Phase 2 (Hans, 2026-05-30): Tag-Editor fuer einen Highlight-
  // Anker. Kleines Floating-Popover mit aktuellen Tags als Chips +
  // Input fuer neue. Submit feuert PATCH /highlights/:anchor/tags,
  // Server passt die MD-Quelle an + sync_for updated die DB-Tabelle.
  async openHighlightTagEditor(anchor, x, y) {
    // Vorhandenes Popover aufraeumen.
    document.querySelectorAll(".highlight-tag-editor").forEach(e => e.remove())
    const pop = document.createElement("div")
    pop.className = "highlight-tag-editor fixed z-50 bg-white border border-slate-200 rounded shadow-lg p-2 text-sm space-y-2"
    pop.style.minWidth = "240px"
    pop.style.left = `${Math.max(8, Math.min(x, window.innerWidth  - 260))}px`
    pop.style.top  = `${Math.max(8, Math.min(y, window.innerHeight - 140))}px`
    pop.innerHTML = `
      <div class="text-xs text-slate-500 flex items-center gap-1">
        <span>${window.t("js.paragraph.tags_for_highlight")}</span>
        <code class="text-slate-400">^${anchor}</code>
      </div>
      <div class="chips flex flex-wrap gap-1"></div>
      <form class="add-form flex items-center gap-1">
        <input type="text" class="add-input flex-1 px-2 py-1 text-xs border border-slate-200 rounded focus:outline-none focus:border-slate-400" placeholder="${window.t("js.paragraph.new_tag_placeholder")}" autocomplete="off" />
        <button type="submit" class="add-btn px-2 py-1 text-xs rounded bg-emerald-600 text-white hover:bg-emerald-700 cursor-pointer">+</button>
      </form>
    `
    document.body.appendChild(pop)

    let tags = []
    const chipsEl = pop.querySelector(".chips")
    const renderChips = () => {
      chipsEl.innerHTML = ""
      if (tags.length === 0) {
        chipsEl.innerHTML = `<span class="text-xs italic text-slate-400">${window.t("js.paragraph.no_tags")}</span>`
        return
      }
      tags.forEach((t, i) => {
        const chip = document.createElement("span")
        chip.className = "inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-slate-100 text-xs"
        chip.innerHTML = `<span>${t}</span><button type="button" class="text-slate-400 hover:text-rose-600 leading-none">×</button>`
        chip.querySelector("button").addEventListener("click", () => {
          tags.splice(i, 1); renderChips(); persist()
        })
        chipsEl.appendChild(chip)
      })
    }

    const persist = async () => {
      const params = new URLSearchParams()
      tags.forEach(t => params.append("tags[]", t))
      // #447 (Hans, 2026-06-01): KI-UUID mitschicken, damit der Server die KI
      // direkt findet — nicht ueber einen KnowledgeItemAnchor-Record, der fuer
      // Highlight-Anker fehlen kann (-> frueher 404 "Konnte Tags nicht speichern").
      params.append("ki", this.uuidValue)
      const res = await fetch(`/highlights/${anchor}/tags`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept":       "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: params.toString()
      })
      if (!res.ok) {
        this.toast(window.t("js.paragraph.tags_save_failed"))
        return false
      }
      const data = await res.json()
      tags = data.tags || []
      renderChips()
      return true
    }

    // Initial-Load. KI-UUID mitgeben, damit bestehende Tags aus dem Body
    // gelesen werden koennen (auch ohne KnowledgeItemAnchor-Record).
    try {
      const r = await fetch(`/highlights/${anchor}/tags?ki=${encodeURIComponent(this.uuidValue)}`, { headers: { "Accept": "application/json" } })
      if (r.ok) tags = (await r.json()).tags || []
    } catch (_) { /* silent */ }
    renderChips()

    const form  = pop.querySelector(".add-form")
    const input = pop.querySelector(".add-input")
    input.focus()
    form.addEventListener("submit", async e => {
      e.preventDefault()
      const v = input.value.trim().toLowerCase().replace(/[^a-z0-9_-]+/g, "")
      if (!v) return
      if (!tags.includes(v)) {
        tags.push(v)
        renderChips()
        await persist()
      }
      input.value = ""
      input.focus()
    })

    // Schliessen bei Aussenklick.
    const onOutside = (e) => {
      if (!pop.contains(e.target)) {
        pop.remove()
        document.removeEventListener("mousedown", onOutside, true)
      }
    }
    setTimeout(() => document.addEventListener("mousedown", onOutside, true), 0)
  }

  toast(message, opts = {}) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-toast-timeout-value", String(opts.ms || 6000))
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-start gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    const inner = opts.html ? message : this.escapeHtml(message)
    div.innerHTML = `<div class="flex-1 min-w-0">${inner}</div>
      <button type="button" data-action="click->toast#dismiss"
              class="text-slate-400 hover:text-white text-lg leading-none">×</button>`
    stack.appendChild(div)
  }

  escapeHtml(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                    .replace(/"/g, "&quot;").replace(/'/g, "&#039;")
  }
}
