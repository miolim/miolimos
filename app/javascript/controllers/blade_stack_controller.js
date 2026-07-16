import { Controller } from "@hotwired/stimulus"
import { BladeStackHistory } from "lib/blade_stack_history"
import { BladeStackSpineMixin } from "lib/blade_stack_spine"
import { BladeStackTrailMixin } from "lib/blade_stack_trail"
import { BladeStackScrollMixin } from "lib/blade_stack_scroll"
import { BladeStackOpenersMixin } from "lib/blade_stack_openers"
import { BladeStackCollapseMixin } from "lib/blade_stack_collapse"
import { BladeStackKeyboardMixin } from "lib/blade_stack_keyboard"
import { BladeStackRoutes } from "lib/blade_stack_routes"
import { BladeStackEditModeMixin } from "lib/blade_stack_edit_mode"
import { BladeStackMobileMixin } from "lib/blade_stack_mobile"
import { BladeStackResizeMixin } from "lib/blade_stack_resize"

// Sliding-Panes-Stack à la Andy Matuschak / Obsidian Sliding Panes:
// horizontal angeordnete Karteikarten, neue Cards rechts angefügt,
// Wikilinks zwischen Cards öffnen rechts daneben statt zu replacen.
//
// **Trail-Modell**: jeder Stack führt einen internen Trail mit, eine
// Sequenz von Stack-States. Jede Mutation (Wikilink-Klick, Card-×,
// fresh openFromList) pushed einen neuen State. Trail-Buttons erlauben
// Schritt zurück / vor — wie Browser-Back/Forward, aber rein client-
// seitig und ohne Browser-History pro Mini-Mutation zu fluten.
//
// Beim "großen Wechsel" (replaceStack) wird der bisherige Trail in die
// localStorage-History abgelegt, dort steht er mit `current`-Index, so
// dass beim Reopen genau die Position wiederhergestellt wird.
//
// Markup:
//   <div data-controller="blade-stack"
//        data-blade-stack-card-url-template-value="/knowledge_items/UUID/card"
//        data-blade-stack-history-storage-key-value="knowledge.stack.history">
//     <div data-blade-stack-target="container" class="flex overflow-x-auto snap-x">
//       …Cards…
//     </div>
//   </div>
class BladeStackController extends Controller {
  static targets = ["container", "trailBack", "trailForward", "trailStep"]
  static values  = {
    // #563 (Hans): die Vorlage wird NUR für nackte KnowledgeItem-UUIDs genutzt
    // (präfixierte Stack-IDs wie task:/document:/list: lösen über _urlForStackId
    // auf). Sie ist auf jeder Seite, die sie setzt, identisch die KI-Card-Route.
    // Default daher direkt diese Route — sonst lieferte eine Seite OHNE das
    // Attribut (z.B. /tasks, /documents) beim Öffnen eines KI-Listeneintrags
    // (Personen!) eine leere URL → kein Blade. Seiten, die das Attribut setzen,
    // überschreiben den Default mit demselben Wert.
    cardUrlTemplate:   { type: String, default: "/knowledge_items/UUID/card" },
    historyStorageKey: { type: String, default: "knowledge.stack.history" },
    // #271: per-User-Vorlieben via Settings/Vorlieben. Layout schreibt
    // hier die Default-Card-Breiten in rem pro Card-Kind, plus die
    // Wheel-Schwellen — die ueberschreiben die hartcodierten Defaults.
    cardWidths:        { type: Object, default: {} },
    wheelThreshold:    { type: Number, default: 20  },
    wheelLockMs:       { type: Number, default: 110 }
  }

  static SPINE_STEP        = 28
  static MAX_TRAIL_LENGTH  = 50    // pro Stack: max 50 Trail-States im Speicher
  // HISTORY_MAX lebt jetzt in lib/blade_stack_history.js (BladeStackHistory).

  connect() {
    // #434 (Hans, 2026-06-01): Die Stack-History haengt am ERSTEN Listen-Blade
    // des Stacks (list:tasks, list:dashboard, …) — nicht mehr pauschal pro
    // Seite. So hat jeder Start-Listen-Typ seinen eigenen Verlauf. Der
    // Seiten-Default (historyStorageKeyValue) bleibt Fallback, wenn das erste
    // Blade keine Liste ist.
    this._pageHistoryKey = this.historyStorageKeyValue
    // Persistenz-Backend; History-Read/Write geht ueber dieses Helper-
    // Objekt, NICHT direkt auf localStorage.
    this.history = new BladeStackHistory(this._effectiveHistoryKey())
    this._syncHistoryKeyAttr()

    // #163 Phase 6a: serverseitig gerenderte Cards koennen doppelte
    // HTML-IDs haben (mehrere `task:42`-Instanzen aus ?stack=task:42,task:42).
    // Vor jedem weiteren Setup uniquen wir die IDs durch.
    this.containerTarget.querySelectorAll(".stack-card").forEach(card => {
      this._uniquifyCardId(card)
      // #163 Phase 6e: Resize-Handle am rechten Card-Rand (nur Desktop),
      // Breite persistiert pro Card-Kind in localStorage.
      this._setupResizeForCard(card)
    })
    // #289: Spine-Top-Icon auf Hover zum Schliessen-Kreuz machen, damit
    // der Schliessen-Klick ohne Mausweg zum Boden geht.
    this._upgradeSpineTopIcons()

    // Trail aus aktuellem DOM initialisieren — was beim Page-Load im
    // Container ist, ist State 0.
    const initial = this.openUuids()
    this.trail        = initial.length ? [initial] : []
    this.currentIndex = initial.length ? 0 : -1

    this.restickify()
    this.applyHighlighting()
    this.refreshTrailControls()
    // #287: Listen-Rows, die einem im Stack offenen Blade entsprechen,
    // fett + Jump-Pfeil-Button.
    this._refreshInStackMarkers()
    // #320 (Hans): Mehrfach-Instanzen markieren — Counter-Badge auf jedem
    // Spine, dessen data-uuid ≥2x im Stack vorkommt.
    this._refreshInstanceCounters()

    // Wenn die Page ohne Stack-Param aufgerufen wurde (z.B. via
    // Sidebar-Klick auf "Wissen"): den letzten Eintrag aus der
    // localStorage-History wiederherstellen, damit der User dort
    // weiterarbeiten kann, wo er aufgehört hat.
    if (initial.length === 0) {
      this.restoreLastFromHistoryIfAny()
    }

    this.popHandler = () => this.syncFromUrl()
    window.addEventListener("popstate", this.popHandler)

    // #434 (Hans, 2026-06-01): Klick auf eine Sidebar-Liste, die GERADE das
    // erste Blade des Stacks ist, setzt den Stack zurueck (Snapshot + frischer
    // Trail) statt zu navigieren/anzuhaengen. Nur wenn es etwas zu resetten
    // gibt (mehr als nur die Liste selbst). Capture-Phase + stopPropagation,
    // damit weder die Default-Navigation noch der blade-link#append-Action
    // (Append-Klickmodus) zusaetzlich feuert.
    this.sidebarResetHandler = (e) => {
      const link = e.target.closest?.("a[data-stack-reset-id]")
      if (!link) return
      const id   = link.dataset.stackResetId
      const open = this.openUuids()
      if (open[0] === id && open.length > 1) {
        e.preventDefault()
        e.stopPropagation()
        this.replaceStack(id)
      }
    }
    document.addEventListener("click", this.sidebarResetHandler, true)

    this.keyHandler = (e) => this.handleKeydown(e)
    window.addEventListener("keydown", this.keyHandler)

    // Aktive Card per focusin (Cursor in Textfeld) oder Pointerdown
    // tracken. Der Active-State wird per data-active="true" markiert
    // und CSS hebt ihn dezent hervor (siehe tailwind/application.css).
    // #202: Klick auf Card-Body (nicht auf Link/Button) scrollt die
    // Card zusätzlich ins Viewport — gleicher Effekt wie Spine-Klick.
    this.focusHandler = (e) => {
      const card = e.target.closest?.(".stack-card")
      if (!card) return
      // #288 follow-up2 (Hans, 2026-05-25): Rechtsklick (button=2) und
      // Middle-Click (button=1) duerfen den active-State NICHT
      // umschreiben — sonst geht der Rechtsklick-Swap (siehe
      // spineContextMenu) auf den gerade rechts-geklickten Spine
      // selbst zurueck statt auf den eigentlichen Vorgaenger.
      if (e.type === "pointerdown" && typeof e.button === "number" && e.button !== 0) return
      // #381 v2 (Hans, 2026-05-26): Auf Mobile uebernimmt native
      // scroll-snap das Card-Positionieren beim Swipe; der Active-Marker
      // wird im scrollend-Listener (_syncActiveCardToScroll, #316)
      // gesetzt. Der pointerdown-Pfad ist hier nur fuer Desktop sinnvoll
      // (Klick-zum-Aktivieren + Scroll-in-View). Auf Mobile sorgt jede
      // pointerdown-Mutation (setActiveCard, scrollCardIntoView) fuer
      // Reibung mit dem nativen Touch-Drag, was sich als Swipe-Delay
      // aeussert. focusin-Pfad bleibt aktiv fuer Cursor-in-Textfeld.
      if (e.type === "pointerdown" && this._mediaMobile?.matches) return
      this.setActiveCard(card)
      if (e.type !== "pointerdown") return
      const onInteractive = e.target.closest(
        // #864 (Hans): Textfelder (input/textarea/contenteditable) ausgenommen,
        // damit ein Klick hinein die teilweise sichtbare Card wie sonst auch
        // vollständig ins Bild scrollt. Nur echte Navigations-/Aktions-Controls
        // (Link/Button/Select/Label/Summary) unterdrücken das Scrollen weiter.
        "a, button, select, label, summary"
      )
      if (!onInteractive) this.scrollCardIntoView(card)
    }
    this.containerTarget.addEventListener("focusin",    this.focusHandler)
    this.containerTarget.addEventListener("pointerdown", this.focusHandler)
    // #288: Rechtsklick auf einen Spine → Swap zur vorherigen Position.
    // Listener auf dem Container, damit auch dynamisch angehaengte
    // Cards/Spines automatisch reagieren.
    this._contextMenuHandler = (e) => this.spineContextMenu(e)
    this.containerTarget.addEventListener("contextmenu", this._contextMenuHandler)
    // #474 (Hans, 2026-06-02): Mobil gibt es keinen Rechtsklick fuer die
    // Spine-Sprung-Navigation. Stattdessen erkennen wir hier per touchend
    // einen Doppel-Tap auf einen Spine (das synthetisierte `dblclick` ist
    // bei zoom-baren Viewports unzuverlaessig). Passive:false, damit wir
    // den Doppel-Tap-Zoom unterdruecken koennen.
    this._spineTouchHandler = (e) => this._onSpineTouchEnd(e)
    this.containerTarget.addEventListener("touchend", this._spineTouchHandler, { passive: false })
    // Initial-Markierung: letzte Card im Stack, falls eine offen ist.
    // #284 v2: nach Reload die aeusserst rechte Card sticky-aware ins
    // Viewport scrollen. v1 nutzte scrollIntoView({inline:"nearest"}) —
    // bei Sticky-Positionierung glaubt der Browser, die Card sei schon
    // sichtbar (rendered position via sticky-Offset), und scrollt nicht.
    // Wir berechnen den Ziel-scrollLeft per kumulativer Card-Breite
    // (Content-Koordinaten, NICHT getBCR der gestickyten Cards) und
    // setzen scrollLeft direkt — kein Smooth, soll beim Reload im
    // richtigen Frame stehen.
    const last = this.containerTarget.querySelector(".stack-card:last-child")
    if (last) {
      this.setActiveCard(last)
      requestAnimationFrame(() => this._scrollLastIntoView(last))
    }

    // #224 6f-3: Diskretes horizontales Scrollen. Wheel-deltaX (Trackpad-
    // 2-Finger-Swipe, Mouse-Tilt-Wheel, Shift+Wheel) wird in Focus-Steps
    // umgesetzt — eine Geste = ein Step. Continuous-Scroll wird unter-
    // drueckt, weil sonst die Card-Position springt waehrend man scrollt.
    // Accumulator + Threshold: Trackpads liefern viele kleine deltaX-
    // Werte pro Frame, wir wollen nur EINEN Step pro „Burst".
    this._wheelAccumX = 0
    this._wheelLockedUntil = 0
    this._onWheel = (e) => this._handleWheel(e)
    this.containerTarget.addEventListener("wheel", this._onWheel, { passive: false })

    // #224 6f-4 v2 (first principles, 2026-05-18): Mobile-Stack ist
    // jetzt native CSS scroll-snap. Browser uebernimmt Swipe-Mechanik —
    // kein touch-JS, kein translateX, kein spine_visible-Toggle.
    // Wir setzen nur das `data-mobile`-Attribut zur CSS-Schaltung
    // und kuemmern uns ums Scrollen-zur-active-Card.
    this._mediaMobile     = window.matchMedia("(max-width: 767px)")
    this._onMobileChange  = () => this._applyMobileLayout()
    this._mediaMobile.addEventListener("change", this._onMobileChange)
    this._applyMobileLayout()

    // #316 (Hans, 2026-05-24): Auf Mobile uebernimmt der Browser das
    // Swipen (scroll-snap), aber der Active-Marker bleibt auf der
    // alten Card haengen — User muss tappen, damit Spine dunkel wird.
    // Hier hooken wir uns in `scrollend` ein und markieren die am
    // weitesten links eingerastete Card als active.
    this._onContainerScrollEnd = () => this._syncActiveCardToScroll()
    this.containerTarget.addEventListener("scrollend", this._onContainerScrollEnd)

    // Externe DOM-Mutationen (Turbo-Stream nach Delete eines KI):
    // Sticky/Highlight/URL aktualisieren, aber KEIN neuer Trail-Step —
    // war keine User-Aktion auf dem Stack selbst.
    this.mutObserver = new MutationObserver(muts => {
      // #232 Phase 1 (B): Waehrend eines Turbo-Page-Morphs NICHT als
      // User-Append behandeln. idiomorph patcht Cards in-place (gleiche
      // ids), aber falls dabei doch childList-Mutationen anfallen, wuerden
      // wir sonst faelschlich scrollen/fokussieren/Trail schreiben. Das
      // Layout zieht stattdessen der turbo:render-Listener unten nach.
      if (this._morphing) return
      const cardsChanged = muts.some(m =>
        Array.from(m.addedNodes).some(n => n.nodeType === 1 && n.matches?.(".stack-card")) ||
        Array.from(m.removedNodes).some(n => n.nodeType === 1 && n.matches?.(".stack-card"))
      )
      if (cardsChanged) {
        // #163 Phase 6e: neue Cards bekommen ihren Resize-Handle.
        // #235 follow-up (2026-05-18): per turbo_stream.append in den
        // Container reingelegte Cards (z.B. Quickadd-Response) wurden
        // bisher nur stickyfiziert, aber nicht ins Viewport gescrollt.
        // Mobile-Effekt: neue Task-Card lag offscreen rechts, User
        // musste manuell swipen. Letzte hinzugefuegte Card jetzt direkt
        // in den Focus scrollen — identisch zum _appendBladeAtUrl-Pfad.
        let lastAdded = null
        muts.forEach(m => {
          m.addedNodes.forEach(n => {
            if (n.nodeType === 1 && n.matches?.(".stack-card")) {
              this._setupResizeForCard(n)
              lastAdded = n
            }
          })
        })
        // #289: Append-Pfad — neue Cards bekommen das Hover-X-Overlay.
        this._upgradeSpineTopIcons()
        // #287: Append-Pfad — Listen-Markierung neu berechnen.
        this._refreshInStackMarkers()
        // #320: Append-Pfad — Mehrfach-Instanzen-Counter neu rechnen.
        this._refreshInstanceCounters()
        this.restickify()
        this.applyHighlighting()
        this.syncUrl({ pushHistory: false })
        if (lastAdded) {
          // #280 follow-up: neu angehaengte Card sofort als active markieren,
          // damit Keyboard-Shortcuts (Cmd/Ctrl+Alt+Pfeil) und visuelle
          // Hervorhebung sofort greifen. Vorher musste der User erst rein-
          // klicken — bei einem Click aus der Suchergebnis-Liste war das
          // unintuitiv.
          this.setActiveCard(lastAdded)
          // #281 v3 (Hans, 2026-05-24): Auto-Collapse VOR dem Scroll,
          // damit der natuerliche Stack klein genug bleibt, dass die
          // neue Card vollstaendig ins Viewport passt. Erst danach
          // restickify und Scroll.
          this._autoCollapseToFitNewCard(lastAdded)
          this.restickify()
          requestAnimationFrame(() => {
            this._scrollCardIntoFocus(lastAdded)
            // #270: Wenn die neu angehaengte Card data-focus-after-add
            // traegt, das entsprechende Eingabefeld fokussieren. Aktuell
            // genutzt vom Dashboard-Quickadd, der eine frische Task-Card
            // einliefert — Cursor soll direkt im Description-Feld stehen.
            this._focusAfterAdd(lastAdded)
          })
        }
      }
    })
    this.mutObserver.observe(this.containerTarget, { childList: true })

    // #190: aktueller Trail muss beim Page-Verlassen in den Verlauf
    // wandern — sonst geht der via appendCard/appendFromList aufgebaute
    // Stand verloren und der nächste Page-Load restored einen veralteten
    // Trail aus dem Verlauf. Sowohl `turbo:before-visit` (Turbo-
    // Navigation) als auch `beforeunload` (Hard-Reload, Tab-close)
    // abdecken; snapshotToHistory ist via finalOf-Dedup idempotent.
    this.snapshotOnLeave = () => this.snapshotToHistory()
    document.addEventListener("turbo:before-visit", this.snapshotOnLeave)
    window.addEventListener("beforeunload", this.snapshotOnLeave)

    // #232 Phase 1 (B): Turbo-8 Page-Morph (Live-Update via broadcast_refresh).
    // Der blade-stack-Knoten bleibt beim Morph erhalten — connect() feuert
    // NICHT neu —, daher das Sticky-Layout hier nachziehen. Das
    // `_morphing`-Flag schuetzt den MutationObserver oben davor, die
    // morph-bedingten In-place-Patches als User-Appends zu deuten.
    this._onBeforeRender = () => {
      this._morphing = true
      // #232 Option A (Hans, 2026-05-31): horizontale Scroll-Position des
      // Stack-Containers merken — sie ist KEIN window-Scroll, den preserviert
      // turbo-refresh-scroll also nicht; ohne das springt der Stack beim
      // Morph zurueck ("Ansicht zurueckgesetzt").
      this._morphScrollLeft = this.containerTarget?.scrollLeft ?? null
    }
    this._onAfterRender  = () => {
      if (!this._morphing) return
      this._morphing = false
      // nach dem DOM-Patch: Sticky-Spine + Highlighting + In-Stack-Marker
      // neu berechnen (Card-Anzahl bleibt gleich, aber Inhalte/Hoehen
      // koennen sich geaendert haben).
      this.restickify()
      this.applyHighlighting()
      this._refreshInStackMarkers()
      // Scroll-Position nach dem Restickify wiederherstellen.
      if (this._morphScrollLeft != null && this.hasContainerTarget) {
        this.containerTarget.scrollLeft = this._morphScrollLeft
      }
    }
    document.addEventListener("turbo:before-render", this._onBeforeRender)
    document.addEventListener("turbo:render", this._onAfterRender)
    // #892 (Hans): Nach einem Turbo-Stream (u.a. dem Spine-Broadcast bei WIP-/
    // Status-Wechsel) das Hover-X-Overlay am Spine neu aufsetzen. Der ersetzte
    // Spine kommt un-upgraded vom Server; der MutationObserver feuert dafür
    // nicht (childList-only, kein subtree). _upgradeSpineTopIcons ist idempotent
    // (data-top-upgraded-Guard) — sonst wäre nach einer Live-Änderung das obere
    // Schließen-Kreuz weg.
    this._onSpineStreamRender = () => requestAnimationFrame(() => this._upgradeSpineTopIcons())
    document.addEventListener("turbo:before-stream-render", this._onSpineStreamRender)

    // #163 Phase 4: Sidebar-Plus-Icons (Append-to-Stack) sollen NUR
    // sichtbar sein, wenn diese Seite einen Blade-Stack hat. Body-Klasse
    // toggled die CSS-Sichtbarkeit, siehe .sidebar-blade-plus in
    // application.css.
    document.body.classList.add("has-blade-stack")

    // #163 Phase 4: Sidebar (separater DOM-Teilbaum, kein Stimulus-
    // Ancestor des blade-stack) dispatcht globale Custom-Events; wir
    // hoeren auf window und routen sie ins normale _appendBladeAtUrl.
    // Erwartetes detail-Shape: { kind: "topic"|"task"|"source", id: String }.
    this._onAppendEvent = async (e) => {
      const { kind, id, sourceListId, anchor, mode: explicitMode } = e.detail || {}
      if (!kind || !id) return
      // #564: kind→(stackId,url) kommt aus der EINEN Routing-Tabelle
      // (lib/blade_stack_routes) — vorher ein eigener Switch, der gegen
      // _urlForStackId driften konnte (#563-Klasse).
      const entry = BladeStackRoutes.forKind(kind, id, { cardUrlTemplate: this.cardUrlTemplateValue })
      if (!entry) {
        // #247 follow-up: bei einem unbekannten kind passiert sonst still
        // gar nichts (Hans-Report). Mit der Warnung ist's einfacher zu
        // erkennen, dass z.B. ein gecachtes altes JS-Bundle das neue
        // Event nicht versteht.
        console.warn("blade-stack: unknown append kind", kind, "from", e.detail)
        return
      }
      const { stackId, url } = entry
      // #224 6f-2: Klick-Semantik haengt davon ab, ob das Event aus
      // einer Listen-Blade kommt (sourceListId gesetzt). Aus Listen-
      // Blade = Sub-Stack-Ersatz (mode=replace_substack), sonst (Sidebar-
      // Plus/Nav-Klick) ganz hinten anhaengen.
      // #218: wenn ein anchor mitkommt (z.B. "task_comment_354" aus den
      // ungelesenen Kommentaren im Dashboard), nach Append/Focus
      // dahinscrollen.
      const fromList       = !!sourceListId
      const sourceListCard = fromList ? document.getElementById(sourceListId) : null
      // #224 6f-2 cleanup: explicit mode aus dem Event hat Vorrang
      // (Plus-Icon-on-Row → "append_to_substack"). Default je nach
      // Kontext: aus Listen-Blade = replace_substack, sonst (Sidebar/
      // Nav-Klick) = append_to_stack.
      const mode = explicitMode || (fromList ? "replace_substack" : "append_to_stack")
      await this._appendBladeAtUrl({
        stackId, url,
        forceNew:       !fromList || mode === "append_to_substack",
        sourceListCard,
        mode
      })
      if (anchor) {
        const card = this.cardForUuid(stackId)
        if (card) {
          // #218: collapsed Card erst aufklappen, sonst wird
          // scrollToAnchorInCard ins Leere zielen.
          this._expandCard(card)
          card.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" })
          this.scrollToAnchorInCard(card, anchor)
        }
      }
      // #224 6f-1: kein Auto-Collapse mehr — Listen-Blade bleibt offen,
      // siehe `_autoCollapseSourceList`. sourceListId beeinflusst nur
      // noch die Append-vs.-Focus-Heuristik oben.
    }
    window.addEventListener("blade-stack:append", this._onAppendEvent)

    // #265: Session-Persistenz vs. Restoration sind exklusiv —
    //   - URL hat ?stack=: das ist die kanonische State, jetzt sofort
    //     persistieren (damit naechstes Mal ohne URL-Param hier landet).
    //   - URL ohne ?stack=: NICHT persistieren (sonst ueberschreibt der
    //     leere Anfangsstand den vorher gemerkten); stattdessen den
    //     gemerkten Stand restaurieren. _appendBladeAtUrl loest Mutations-
    //     Observer + syncUrl aus, der dann wieder persistiert.
    const _urlStack = new URL(window.location.href).searchParams.get("stack")
    if (_urlStack) {
      this._persistSession(this.openUuids())
    } else {
      this._restoreSessionStackIfNeeded()
    }
  }

  disconnect() {
    if (this.popHandler) window.removeEventListener("popstate", this.popHandler)
    if (this.sidebarResetHandler) document.removeEventListener("click", this.sidebarResetHandler, true)
    if (this.keyHandler) window.removeEventListener("keydown", this.keyHandler)
    if (this.focusHandler) {
      this.containerTarget.removeEventListener("focusin",    this.focusHandler)
      this.containerTarget.removeEventListener("pointerdown", this.focusHandler)
    }
    if (this._contextMenuHandler) {
      this.containerTarget.removeEventListener("contextmenu", this._contextMenuHandler)
    }
    if (this._spineTouchHandler) {
      this.containerTarget.removeEventListener("touchend", this._spineTouchHandler)
    }
    if (this._onWheel) {
      this.containerTarget.removeEventListener("wheel", this._onWheel)
    }
    if (this._mediaMobile && this._onMobileChange) {
      this._mediaMobile.removeEventListener("change", this._onMobileChange)
    }
    if (this._onContainerScrollEnd) {
      this.containerTarget.removeEventListener("scrollend", this._onContainerScrollEnd)
    }
    // #232 Phase 1 (B): Morph-Listener abmelden.
    if (this._onBeforeRender) document.removeEventListener("turbo:before-render", this._onBeforeRender)
    if (this._onAfterRender)  document.removeEventListener("turbo:render", this._onAfterRender)
    if (this._onSpineStreamRender) document.removeEventListener("turbo:before-stream-render", this._onSpineStreamRender)
    if (this.snapshotOnLeave) {
      document.removeEventListener("turbo:before-visit", this.snapshotOnLeave)
      window.removeEventListener("beforeunload", this.snapshotOnLeave)
      // Beim disconnect noch einmal snapshotten — z.B. wenn der
      // Controller durch turbo-frame-Replace ausgehängt wird, ohne
      // dass turbo:before-visit feuert.
      this.snapshotToHistory()
    }
    this.mutObserver?.disconnect()
    this._dismissCloseMenu()
    document.body.classList.remove("has-blade-stack")
    if (this._onAppendEvent) window.removeEventListener("blade-stack:append", this._onAppendEvent)
  }

  // ─── Aktive Card ────────────────────────────────────────────────

  setActiveCard(card) {
    // #288 v4 (Hans, 2026-05-25): vor dem Umschalten den bisherigen
    // active-Spine als _prevActiveUuid merken (unabhaengig davon, WIE
    // der bisherige Focus entstanden ist). Damit funktioniert der
    // Rechtsklick-Swap auch nach Scroll, focusin, Keyboard etc.
    // Nur fortschreiben, wenn der active-State tatsaechlich wechselt
    // und der bisherige active eine echte Card war (nicht null).
    const prev = this.containerTarget.querySelector('.stack-card[data-active="true"]')
    if (prev && prev !== card) {
      this._prevActiveUuid = prev.dataset.uuid || null
    }
    this.containerTarget.querySelectorAll(".stack-card").forEach(c => {
      c.dataset.active = (c === card) ? "true" : "false"
    })
  }

  activeCard() {
    return this.containerTarget.querySelector('.stack-card[data-active="true"]') ||
           this.containerTarget.querySelector(".stack-card:last-child")
  }

  // #316 (Hans, 2026-05-24): Mobile-Swipe-end → ermitteln, welche Card
  // jetzt im Viewport eingerastet ist, und sie als active markieren.
  // Auf Desktop kein-op, weil Active dort via Klick getrackt wird.
  // _syncActiveCardToScroll liegt in BladeStackScrollMixin (#529).

  // ─── Public Actions (von DOM-Events ausgelöst) ──────────────────

  // #321 (Hans): Card duplizieren — laedt eine zweite Instanz derselben
  // Card-UUID und fuegt sie DIREKT HINTER die Original-Card ein.
  // v2 (Hans-Spec): nicht ans Stack-Ende, sondern unmittelbar nach
  // der Original-Card.
  async duplicateCard(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    const sourceCard = btn.closest(".stack-card")
    // #620 (Hans): Die LIVE-uuid der umgebenden Karte gewinnt — das
    // statische data-target-uuid des Buttons kennt z.B. den aktuell
    // gewaehlten Topic-Reiter nicht (Tab-Suffix in der Card-uuid);
    // die Dublette fiel deshalb auf den Default-Reiter zurueck.
    const uuid = sourceCard?.dataset?.uuid || btn.dataset.targetUuid
    if (!uuid) return
    // #321 v3: cardUrlTemplate kennt nur KnowledgeItem-Routen. Tasks etc.
    // brauchen _urlForStackId, das das Stack-Id-Prefix (`task:`,
    // `topic:`, etc.) in die richtige Route uebersetzt.
    const url = this._urlForStackId(uuid)
    if (!url) { console.warn("duplicateCard: no URL for", uuid); return }
    const res = await fetch(url, { headers: { Accept: "text/html" } })
    if (!res.ok) { console.warn("duplicateCard: fetch failed", res.status); return }
    const html = await res.text()
    const { nodes, card } = this._parseCardHtml(html)   // #621
    if (!card) return
    if (sourceCard) {
      let ref = sourceCard.nextSibling
      nodes.forEach(n => sourceCard.parentNode.insertBefore(n, ref))
    } else {
      nodes.forEach(n => this.containerTarget.appendChild(n))
    }
    this.pushTrailState()
  }

  // #1005 (Hans): Card an den Dashboard-Stack anhängen — OHNE dorthin zu
  // wechseln, nur ein Toast. Mechanik: die beiden Dashboard-Restore-Keys
  // (sessionStorage `stack./dashboard` gewinnt beim Restore, localStorage
  // `stack.last./dashboard` ist der Neustart-Fallback — siehe
  // blade_stack_trail.js) um die Card-uuid erweitern. Ist das Dashboard die
  // aktuelle Seite, wird die Card stattdessen direkt angehängt. Grenze: eine
  // in einem ANDEREN Tab offene Dashboard-Session überschreibt die Keys beim
  // nächsten eigenen Stack-Wechsel — akzeptiert (Single-User-Praxis).
  appendToDashboard(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    const sourceCard = btn.closest(".stack-card")
    // Live-uuid der Card gewinnt (Tab-Suffix etc.), wie beim Duplizieren (#620).
    const uuid = sourceCard?.dataset?.uuid || btn.dataset.targetUuid
    if (!uuid) return
    if (window.location.pathname === "/dashboard") {
      this.appendStackIds([uuid])
    } else {
      const SESSION_KEY = "stack./dashboard"
      const LAST_KEY    = "stack.last./dashboard"
      const read = (store, key) => {
        try { return (store.getItem(key) || "").split(",").map(s => s.trim()).filter(Boolean) }
        catch (_) { return [] }
      }
      const sess = read(sessionStorage, SESSION_KEY)
      const base = sess.length ? sess : read(localStorage, LAST_KEY)
      const ids  = base.length ? base : ["list:dashboard"]
      if (!ids.includes(uuid)) ids.push(uuid)
      const val = ids.join(",")
      try { sessionStorage.setItem(SESSION_KEY, val) } catch (_) { /* silent */ }
      try { localStorage.setItem(LAST_KEY, val) } catch (_) { /* silent */ }
    }
    this._flashToast(window.t("js.blade_stack.appended_to_dashboard"))
  }

  // #1005: Toast aus dem Client (Muster copy_clipboard_controller#flashToast).
  _flashToast(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    div.innerHTML = `<span class="flex-1 min-w-0">${message}</span>
      <button type="button" data-action="click->toast#dismiss"
              class="text-slate-400 hover:text-white text-lg leading-none">×</button>`
    stack.appendChild(div)
  }

  // Klick auf einen Wikilink innerhalb einer Card.
  async openInStack(event) {
    event.preventDefault()
    const link = event.currentTarget
    const uuid = link.dataset.targetUuid
    const blockAnchor = link.dataset.targetAnchor || null
    if (!uuid) return

    // Wenn die Ziel-Card schon offen ist: hin scrollen statt neu laden.
    const existing = this.cardForUuid(uuid)
    if (existing) {
      existing.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" })
      this.setActiveCard(existing)
      if (blockAnchor) this.scrollToAnchorInCard(existing, blockAnchor)
      return
    }

    // #362 (Hans, 2026-05-25): Reference-Blade (refs:ki:* / refs:topic:*)
    // wird DIREKT RECHTS der aufrufenden Card geoeffnet — sonst landet
    // die Referenz weit weg vom Kontext. Andere openInStack-Klicks
    // (Wikilinks etc.) behalten das alte End-Append-Verhalten.
    const sourceCard = link.closest(".stack-card")
    if (uuid.startsWith("refs:") && sourceCard) {
      await this.appendCardAfter(uuid, sourceCard)
      this.pushTrailState()
      this._collapseListIfExpanded()
      if (blockAnchor) {
        const fresh = this.cardForUuid(uuid)
        if (fresh) {
          this.setActiveCard(fresh)
          this.scrollToAnchorInCard(fresh, blockAnchor)
        }
      }
      return
    }

    // #312 follow-up (Hans): Wikilink-Klick laesst den Stack stehen
    // und appendet die Ziel-Card am ENDE — kein Substack-Truncate
    // mehr. Vorher schnitt `truncateAfter(anchorCard)` alles nach der
    // klickenden Card weg und ersetzte es durch das Linkziel; das
    // zerstoerte den Sub-Stack-Kontext. Schon-offene Karten werden
    // weiter oben in dieser Methode per cardForUuid abgefangen.
    await this.appendCard(uuid)
    this.pushTrailState()
    this._collapseListIfExpanded()
    if (blockAnchor) {
      const fresh = this.cardForUuid(uuid)
      if (fresh) {
        this.setActiveCard(fresh)
        this.scrollToAnchorInCard(fresh, blockAnchor)
      }
    }
  }

  // Scrollt das innere Scroll-Container der Card so, dass der Block
  // mit `id="<anchor>"` sichtbar wird, und flasht ihn kurz hervor.
  // Aufrufer hat bereits dafür gesorgt, dass die Card horizontal im
  // Viewport ist (scrollIntoView).
  // scrollToAnchorInCard liegt in BladeStackScrollMixin (#529).

  // Klick auf "+ Neues Wissen": new-Card-Fragment vom Server holen
  // und am Stack-Ende anfügen. Edit-Form ist im Fragment enthalten;
  // beim Save liefert der Server einen Stream, der die Placeholder-
  // Card durch die echte ersetzt + Listen-Row prependet.
  async openNewCard(event) {
    event.preventDefault()
    const url = event.currentTarget.getAttribute("href") ||
                event.currentTarget.dataset.url
    if (!url) return
    // Bereits offene new-Card → fokussieren statt doppelt anhängen.
    const existing = this.cardForUuid("new")
    if (existing) {
      existing.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" })
      existing.querySelector("input[name='title']")?.focus()
      return
    }
    const res = await fetch(url, { headers: { "Accept": "text/html" } })
    if (!res.ok) return
    const html = await res.text()
    const tpl = document.createElement("template")
    tpl.innerHTML = html.trim()
    const card = tpl.content.firstElementChild
    if (!card) return
    const wasEmpty = this.openUuids().length === 0
    this.containerTarget.appendChild(card)
    this.restickify()
    // #202: Sticky-Positioning verschiebt die Card visuell, sodass
    // card.scrollIntoView() oft glaubt, sie sei bereits sichtbar und
    // nichts tut — ergo bleibt die neue Card halb angeschnitten rechts.
    // Direkt auf scrollWidth scrollen klappt zuverlaessig, weil das den
    // Container ans rechte Ende schiebt (= neue Card).
    requestAnimationFrame(() => {
      if (wasEmpty) this.containerTarget.scrollLeft = 0
      else this.containerTarget.scrollTo({ left: this.containerTarget.scrollWidth, behavior: "smooth" })
      card.querySelector("input[name='title']")?.focus()
    })
  }

  // × an einer Card.
  closeCard(event) {
    event.preventDefault()
    // #240: closeCard kann jetzt auf einem Button im Spine-Aside sitzen,
    // der selbst click->focusCard listened — Propagation stoppen, sonst
    // fokussiert die Stack-Logik die gerade entfernte Card.
    event.stopPropagation()
    const card = event.currentTarget.closest("[data-uuid]")
    if (!card) return
    this._closeCardElement(card)
  }

  // #1032 (Hans): Unteres Spine-X — auf dem Desktop öffnet der Klick ein
  // kleines Menü (Diese Card schließen / Diese Card und alle rechts davon
  // schließen) statt sofort zu schließen. Mobil bleibt der Direkt-Close.
  closeCardMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    const card = event.currentTarget.closest("[data-uuid]")
    if (!card) return
    if (!this._isDesktop()) { this._closeCardElement(card); return }
    // Zweiter Klick auf denselben Trigger = Toggle zu (der Outside-Click-
    // Handler ignoriert den Trigger, sonst würde er dismiss + reopen).
    if (this._closeMenuEl) { this._dismissCloseMenu(); return }
    this._openCloseMenu(event.currentTarget, card)
  }

  _openCloseMenu(trigger, card) {
    const hasRight = !!(card.nextElementSibling?.classList?.contains("stack-card"))
    const menu = document.createElement("div")
    menu.className = "fixed z-50 bg-white border border-slate-200 rounded shadow-lg py-1 min-w-52 text-sm text-slate-700"
    const addItem = (label, enabled, onPick) => {
      const b = document.createElement("button")
      b.type = "button"
      b.className = "w-full text-left block px-3 py-1.5 bg-transparent border-0 cursor-pointer hover:bg-slate-50 disabled:opacity-40 disabled:cursor-default disabled:hover:bg-transparent"
      b.textContent = label
      b.disabled = !enabled
      b.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this._dismissCloseMenu()
        onPick()
      })
      menu.appendChild(b)
    }
    addItem("Diese Card schließen", true, () => this._closeCardElement(card))
    addItem("Diese Card und alle rechts davon schließen", hasRight, () => this._closeCardsFrom(card))
    document.body.appendChild(menu)
    // Über dem Trigger positionieren (das X sitzt am Card-Boden), links-
    // bündig zum Trigger, in den Viewport geclampt.
    const r = trigger.getBoundingClientRect()
    let top = r.top - menu.offsetHeight - 4
    if (top < 8) top = r.bottom + 4
    const left = Math.max(8, Math.min(r.left, window.innerWidth - menu.offsetWidth - 8))
    menu.style.top = `${Math.round(top)}px`
    menu.style.left = `${Math.round(left)}px`
    this._closeMenuEl = menu
    this._closeMenuTrigger = trigger
    this._closeMenuDismiss = (e) => {
      if (e.type === "keydown" && e.key !== "Escape") return
      if (e.type === "click" && (menu.contains(e.target) || this._closeMenuTrigger?.contains(e.target))) return
      this._dismissCloseMenu()
    }
    document.addEventListener("click", this._closeMenuDismiss, true)
    document.addEventListener("keydown", this._closeMenuDismiss)
    window.addEventListener("scroll", this._closeMenuDismiss, true)
    window.addEventListener("resize", this._closeMenuDismiss)
  }

  _dismissCloseMenu() {
    if (!this._closeMenuEl) return
    this._closeMenuEl.remove()
    this._closeMenuEl = null
    this._closeMenuTrigger = null
    document.removeEventListener("click", this._closeMenuDismiss, true)
    document.removeEventListener("keydown", this._closeMenuDismiss)
    window.removeEventListener("scroll", this._closeMenuDismiss, true)
    window.removeEventListener("resize", this._closeMenuDismiss)
  }

  // #1032: die Card selbst plus alle Cards rechts davon schließen.
  _closeCardsFrom(card) {
    const cards = [card]
    let el = card.nextElementSibling
    while (el) {
      if (el.classList?.contains("stack-card")) cards.push(el)
      el = el.nextElementSibling
    }
    this._closeCardElements(cards)
  }

  // #593 (Hans, 2026-06-10): Entwurfs-Schutz für Stack-Mutationen. Turbo-
  // Visits deckt dirty-warn global ab; Card-Remove/Replace im Stack läuft
  // aber an Turbo vorbei (fetch + DOM) und hat Entwürfe kommentarlos
  // verworfen. cards = Element(e), die gleich aus dem DOM fliegen; true =
  // weitermachen (nichts dirty oder Nutzer hat das Verwerfen bestätigt).
  _confirmDiscardDrafts(cards) {
    const els = (Array.isArray(cards) ? cards : [cards]).filter(Boolean)
    let count = 0
    for (const el of els) {
      if (el.matches?.('[data-dirty="true"]')) count += 1
      count += el.querySelectorAll?.('[data-dirty="true"]').length || 0
    }
    if (count === 0) return true
    return window.confirm(count > 1
      ? `Es gibt ungespeicherte Änderungen in ${count} Bereichen. Trotzdem fortfahren?`
      : "Es gibt ungespeicherte Änderungen. Trotzdem fortfahren?")
  }

  // #289: Close-Logik raus aus closeCard(), damit Alt+C ohne Click-Event
  // dasselbe Verhalten triggern kann.
  // #358 (Hans, 2026-05-25): nach Close bekommt die linke Nachbarcard
  // den Focus; existiert keine links, dann die rechte.
  // #1032: auf mehrere Cards verallgemeinert (Menü „Diese Card und alle
  // rechts davon schließen") — EIN Entwurfs-Confirm über alle Cards,
  // Focus landet auf dem linken Nachbarn der ersten geschlossenen Card.
  _closeCardElement(card) {
    this._closeCardElements([card])
  }

  _closeCardElements(cards) {
    cards = cards.filter(c => c && !c.classList.contains("is-closing"))  // Doppelklick-Schutz
    if (!cards.length) return
    if (!this._confirmDiscardDrafts(cards)) return
    // Nachbar vorab bestimmen — `previousElementSibling` der ersten Card
    // ist die Card links davon. Falls keine da (= Card war erste im
    // Stack), nehmen wir die rechts von der letzten geschlossenen.
    const first = cards[0]
    const last  = cards[cards.length - 1]
    const focusNext = (first.previousElementSibling?.classList?.contains("stack-card")
                        ? first.previousElementSibling
                        : null)
                       || (last.nextElementSibling?.classList?.contains("stack-card")
                            ? last.nextElementSibling
                            : null)

    // #256: Smooth-Close. Auf Mobile (scroll-snap-Layout) wuerde eine
    // Breiten-Animation nicht passen — dort sofort entfernen. Auf Desktop
    // `is-closing`-Klasse setzen: CSS gleitet Breite → 0 + Opacity → 0,
    // die Nachbar-Cards ruecken durch den Flex-Reflow weich nach. Nach
    // der Transition (oder via Timeout-Fallback) raus aus dem DOM.
    if (this._mediaMobile?.matches) {
      cards.forEach(c => c.remove())
      if (focusNext) {
        this.setActiveCard(focusNext)
        this._scrollCardIntoFocus(focusNext)
      }
      this.pushTrailState()
      return
    }
    let pending = cards.length
    const finishAll = () => {
      // #358: Focus auf Nachbar setzen nachdem die alten Cards weg sind.
      if (focusNext && focusNext.isConnected) {
        this.setActiveCard(focusNext)
        this._scrollCardIntoFocus(focusNext)
      }
      this.pushTrailState()
    }
    cards.forEach(card => {
      // #256 v2: Inner-Content einfrieren, bevor die Card auf Breite 0
      // collapsed. Sonst wuerde der Body (flex-1, min-w-0) jeden Frame
      // neu umbrechen waehrend die Card schmaler wird — genau das Ruckeln.
      // Mit flex:0 0 <px> behalten Spine + Body ihre Groesse und werden
      // einfach vom card-overflow:hidden sauber abgeschnitten.
      card.querySelectorAll(":scope > *").forEach(child => {
        child.style.flex = `0 0 ${Math.round(child.getBoundingClientRect().width)}px`
      })
      card.classList.add("is-closing")
      let removed = false
      const finish = () => {
        if (removed) return
        removed = true
        card.removeEventListener("transitionend", finish)
        card.remove()
        pending -= 1
        if (pending === 0) finishAll()
      }
      card.addEventListener("transitionend", finish)
      setTimeout(finish, 320)  // Fallback, falls transitionend nicht feuert
    })
  }

  // Klick auf einen Spine: Card aus dem Stapel zurück in den Mittel-
  // Viewport scrollen. Keine Trail-Mutation — Stack-Komposition bleibt.
  scrollToCard(event) {
    event.preventDefault()
    const card = event.currentTarget.closest("[data-uuid]")
    if (!card) return
    this.scrollCardIntoView(card)
  }

  // #224 (#391): Spine-Single-Click setzt Focus auf die Card (und
  // scrollt sie ins Viewport), ohne Collapse-State zu toggeln.
  // Double-Click bleibt der Collapse-Toggle (siehe toggleCollapse).
  // Hans-Spec 2026-05-19: Toggle in BEIDEN Richtungen via dblclick —
  // auto-decollapse beim Single-Klick war unintuitiv und ist raus.
  focusCard(event) {
    event.preventDefault()
    const card = event.currentTarget.closest("[data-uuid]")
    if (!card) return
    // #902 (Hans, 2026-07-08): Ein einfacher Klick auf einen EINGEKLAPPTEN
    // Spine klappt die Card wieder aus — der Collapse-Balken (mit dem
    // arrow-right-from-line-Icon) IST damit der Ausklapp-Button, gleiche
    // Aktion wie der Doppelklick. Wir merken uns den Zeitpunkt, damit das
    // vom Doppelklick nachfolgende `dblclick` die Card nicht sofort wieder
    // einklappt (siehe Guard in toggleCollapse).
    if (card.dataset.collapsed === "true") {
      this.toggleCollapse(event)   // klappt aus
      // Flag ERST nach dem Expand setzen — sonst wuerde der Guard in
      // toggleCollapse diesen eigenen Expand-Aufruf verschlucken.
      this._expandViaClick = { uuid: card.dataset.uuid, t: event.timeStamp }
      return
    }
    // #288 follow-up (Hans, 2026-05-24): Linksklick auf den BEREITS
    // aktiven Spine ist ein No-Op — sonst wuerde der erneute Klick
    // den Prev-Slot mit dem aktuellen Wert ueberschreiben, und der
    // Rechtsklick-Swap hat keinen sinnvollen Toggle-Partner mehr.
    if (card.dataset.active === "true") return
    this.scrollCardIntoView(card)
    this.setActiveCard(card)
  }

  // #288 v4 (Hans, 2026-05-25): Rechtsklick auf irgendeinen Spine →
  // springt zum zuvor aktiven Blade (unabhaengig davon, wie der
  // Focus dorthin kam — Klick, Scroll, focusin). Wiederholter
  // Rechtsklick toggelt zwischen aktuellem und vorherigem Blade.
  spineContextMenu(event) {
    if (!event.target.closest?.(".stack-spine")) return
    event.preventDefault()
    const targetUuid = this._prevActiveUuid
    if (!targetUuid) return
    const card = this.containerTarget.querySelector(`.stack-card[data-uuid="${CSS.escape(targetUuid)}"]`)
    if (!card) return
    // setActiveCard schreibt automatisch den aktuellen active auf
    // `_prevActiveUuid` zurueck → Toggle-Verhalten beim naechsten
    // Rechtsklick.
    this.setActiveCard(card)
    this.scrollCardIntoView(card)
  }

  // #474 (Hans, 2026-06-02): Mobiles Gegenstueck zum Rechtsklick-Sprung.
  // Doppel-Tap auf einen Spine erkennen (zwei touchends auf demselben
  // Spine binnen ~350ms) und navigieren:
  //   - Doppel-Tap auf irgendeinen Spine        -> erstes Blade im Stack
  //   - Doppel-Tap auf den Spine des 1. Blades  -> zuletzt fokussiertes
  // Nur mobil (Desktop hat Rechtsklick). preventDefault unterdrueckt den
  // Doppel-Tap-Zoom.
  _onSpineTouchEnd(event) {
    if (this._isDesktop()) return
    const spine = event.target?.closest?.(".stack-spine")
    if (!spine) { this._lastSpineTap = null; return }
    const card = spine.closest(".stack-card[data-uuid]")
    if (!card) { this._lastSpineTap = null; return }
    const now  = event.timeStamp
    const prev = this._lastSpineTap
    if (prev && prev.card === card && (now - prev.t) < 350) {
      event.preventDefault()
      this._lastSpineTap = null
      this._spineJumpMobile(card)
    } else {
      this._lastSpineTap = { card, t: now }
    }
  }

  _spineJumpMobile(card) {
    const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card[data-uuid]"))
    if (!cards.length) return
    const first = cards[0]
    let target
    if (card === first) {
      // Doppel-Tap auf das erste Blade -> zurueck zum zuvor fokussierten.
      const prevUuid = this._prevActiveUuid
      target = prevUuid &&
        this.containerTarget.querySelector(`.stack-card[data-uuid="${CSS.escape(prevUuid)}"]`)
      if (!target || target === first) return
    } else {
      target = first
    }
    this.setActiveCard(target)
    this.scrollCardIntoView(target)
  }

  // Gemeinsamer Helper für Spine-Klick und #202: Click-auf-Card-Body.
  // Klick auf [[Neuer Name]]: legt Item an + appended sofort. Eine
  // Trail-Mutation (truncateAfter + appendCard).
  async openMissing(event) {
    event.preventDefault()
    const link  = event.currentTarget
    const title = link.dataset.targetTitle
    if (!title) return

    const body = new URLSearchParams()
    body.set("title", title)

    const res = await fetch("/knowledge_items/wikilink_create", {
      method: "POST",
      headers: {
        "Content-Type":  "application/x-www-form-urlencoded",
        "Accept":        "application/json",
        "X-CSRF-Token":  document.querySelector("meta[name='csrf-token']")?.content
      },
      body: body.toString()
    })
    if (!res.ok) { console.warn("wikilink_create failed:", res.status); return }
    const data = await res.json()
    if (!data.uuid) return

    // #312 follow-up (Hans): kein Substack-Truncate beim Wikilink-Klick;
    // neue KI laendet ans Ende des Stacks.
    await this.appendCard(data.uuid)

    // Den geklickten Link in-place upgraden
    link.classList.remove("wikilink-missing", "text-rose-600")
    link.classList.add("text-emerald-700", "underline")
    link.dataset.targetUuid = data.uuid
    delete link.dataset.targetTitle
    link.setAttribute("data-action", "click->blade-stack#openInStack")
    link.setAttribute("href", `/knowledge_items/${data.uuid}`)
    link.removeAttribute("title")

    this.pushTrailState()
  }

  // Trail-Buttons + Tasten-Shortcut.
  // trailBack/trailForward sind in BladeStackTrailMixin definiert
  // (#378 Phase 9). Stimulus findet sie ueber den Prototype-Chain.

  // Globaler Keyboard-Handler — behandelt Stack-Shortcuts. Ignoriert
  // Pfeiltasten in Textfeldern, sodass Cursor-Navigation im Editor
  // funktioniert (außer mit Modifier-Combos).
  // handleKeydown + isTextEditing liegen in BladeStackKeyboardMixin
  // (lib/blade_stack_keyboard.js, #529). Der in connect() gebundene
  // this.keyHandler = e => this.handleKeydown(e) löst über die
  // Prototype-Chain auf.

  // #803: activeEditForm/submitForm/toggleEditPreview/swapToEditMode -> BladeStackEditModeMixin (lib/blade_stack_edit_mode.js)

  // Aktive Card eins weiter (delta = -1 / +1) und scrollt sie so in den
  // Viewport, dass sie nicht von den sticky-Spines der links/rechts
  // davor liegenden Cards verdeckt ist.
  // #224 6f-3: delta uebersetzt direkt in die Focus-Richtung. delta>0 =
  // "next" (Focus wandert nach rechts, Card soll rechtsbuendig stehen),
  // delta<0 = "prev" (linksbuendig). Direction wird an scrollCardIntoView
  // weitergereicht, damit der Anchor stimmt.
  moveActive(delta) {
    const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
    if (cards.length === 0) return
    // #224 6f-4 v2: Mobile-Shortcut scrollt zur Nachbar-Card via
    // nativem scrollLeft + scroll-snap. Browser snappt automatisch.
    if (this._mediaMobile?.matches) {
      const idx = Math.max(0, cards.findIndex(c => c.dataset.active === "true"))
      const targetIdx = Math.min(cards.length - 1, Math.max(0, idx + delta))
      const next = cards[targetIdx]
      if (!next || next === cards[idx]) return
      this.setActiveCard(next)
      next.scrollIntoView({ behavior: "smooth", inline: "start", block: "nearest" })
      return
    }
    const idx = Math.max(0, cards.findIndex(c => c.dataset.active === "true"))
    const targetIdx = Math.min(cards.length - 1, Math.max(0, idx + delta))
    const next = cards[targetIdx]
    if (!next || next === cards[idx]) return
    this.setActiveCard(next)
    this.scrollCardIntoView(next, targetIdx, cards.length, delta > 0 ? "next" : "prev")
  }

  // #293 follow-up v3 (Hans, 2026-05-24): Position der aktiven Card im
  // Stack verschieben. delta=+1 → nach rechts mit naechster Card
  // tauschen; delta=-1 → nach links. Card-Identitaet (data-active)
  // bleibt; Trail/URL werden ueber pushTrailState aktualisiert. Keine
  // Animation — DOM-Swap ist atomar, scroll-snap snappt selber.
  //
  // v3.1 (Hans-Report): nach Rechts-Swap blieb der Active-Marker auf
  // der falschen Card haengen. Ursache: insertBefore feuert eine
  // MutationRecord (removed+added) am verschobenen Element. Der
  // MutationObserver oben erkennt das als "neue Card" und ruft selber
  // setActiveCard auf lastAdded auf — was die verschobene Nachbar-Card
  // ist (delta=+1) statt unserer. Workaround: wir setzen Active in
  // einem requestAnimationFrame, NACH dem Observer-Lauf.
  _moveActiveCardPosition(delta) {
    const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
    if (cards.length < 2) return
    const idx = cards.findIndex(c => c.dataset.active === "true")
    if (idx < 0) return
    const targetIdx = idx + delta
    if (targetIdx < 0 || targetIdx >= cards.length) return
    const me   = cards[idx]
    const swap = cards[targetIdx]
    if (delta > 0) {
      // nach me wird die Nachbar-Card EINGE-SCHOBEN (= me rueckt nach hinten).
      me.parentNode.insertBefore(swap, me)
    } else {
      me.parentNode.insertBefore(me, swap)
    }
    // requestAnimationFrame, damit der MutationObserver erst seinen
    // setActiveCard(lastAdded) macht und wir dann das letzte Wort haben.
    requestAnimationFrame(() => {
      this.setActiveCard(me)
      this._scrollCardIntoFocus(me)
    })
    this.pushTrailState()
    this.syncUrl({ pushHistory: false })
  }

  // #212: Bis Mai 2026 existierten zwei `scrollCardIntoView`-Methoden in
  // dieser Klasse (eine einfache fuer Spine-Click, eine sticky-aware
  // fuer moveActive). JS hat die zweite Definition stillschweigend ueber
  // die erste gehoben, weshalb der Spine-Click ohne idx/total aufrief
  // → NaN-Math → kein Scroll. Jetzt eine Funktion, die idx/total
  // optional ableitet, wenn sie nicht uebergeben wurden.
  //
  // #224 6f-3: Anchor-Logic je nach Direction.
  // - direction="next" → rechtsbuendig (minScroll). Card kommt von rechts
  //   ins Bild, anliegend am Bildschirmrand; Vorgaenger-Spines stapeln
  //   sich links.
  // - direction="prev" → linksbuendig (maxScroll). Card kommt von links
  //   ins Bild, anliegend an der Navi-Leiste; Nachfolger-Spines stapeln
  //   sich rechts.
  // - direction unset → nearest-Verhalten wie vorher (Spine-Click, falls
  //   die Card im Sticky-Bereich verschwindet, wird sie zurueckgeholt).
  // Wenn die Card schon vollstaendig zwischen den Spines sichtbar ist
  // (current liegt im [minScroll, maxScroll]-Bereich), wird NICHT
  // gescrollt — Hans's Spec: „Position/Groesse aendert sich nicht,
  // solange die Card vollstaendig sichtbar ist".
  // scrollCardIntoView und _scrollLastIntoView liegen in
  // BladeStackScrollMixin (lib/blade_stack_scroll.js, #529) — via
  // Object.assign auf das Prototype gemixt, `this`-gebunden, reines Code-Move.

  // Spine-Marker-Logic (in-stack-Klasse, Jump-Pfeil, Instance-Counter,
  // Spine-Top-Close, kind-to-uuid-Mapping) ist in `lib/blade_stack_spine.js`
  // ausgelagert (#378 Phase 8) und wird unten auf die Class-Prototype
  // gemixt. Methoden bleiben `this`-gebunden, ohne Verhaltensaenderung.

  // #281 v3 (Hans, 2026-05-24): noop-Stub. Auto-Collapse hilft nicht
  // wirklich, weil die Sticky-Left-Position fest am Index haengt
  // (i*step), unabhaengig vom Collapse-State der Vorgaenger-Cards.
  // Die eigentliche Visibility-Sicherung uebernimmt der sticky-left-
  // Clamp + scrollLeftMax-Target in _scrollLastIntoView.
  _autoCollapseToFitNewCard(_newCard) { /* no-op */ }

  // openShortcutHelp liegt in BladeStackKeyboardMixin (#529).

  // ─── Public API (vom Liste-Klick + Drawer aufgerufen) ───────────

  // openFromList, openSource, openTask, openTopic, openAwaiting,
  // openCommunication liegen in BladeStackOpenersMixin
  // (lib/blade_stack_openers.js, #529) — via Object.assign aufs Prototype
  // gemixt, Stimulus findet die data-action-Handler über die Prototype-Chain.

  // Gemeinsamer Helfer fuer openSource/openTask/etc.
  //
  // #163 Phase 6a: zwei Modi
  //   forceNew=false (Default) — wenn eine Card mit dieser stackId schon
  //     offen ist, scrolle dahin (fokussieren). Sonst hole und appende.
  //   forceNew=true (Plus-Icon-Klick aus Sidebar/Listen-Plus) — IMMER
  //     eine neue Instanz appenden, auch wenn eine schon offen ist. Die
  //     neue Card kriegt eine eindeutige HTML-ID via _uniquifyCardId.
  // #224 6f-2: Append/Replace-Modi.
  //   mode="append_to_stack"     — Default; Card kommt ans Container-Ende.
  //   mode="replace_substack"    — Listen-Item-Klick; alles zwischen
  //                                sourceListCard und naechstem list-Blade
  //                                wird durch die neue Card ersetzt.
  //   mode="append_to_substack"  — Plus an einem Listen-Item; Card wird
  //                                vor dem naechsten list-Blade eingefuegt
  //                                (oder ans Container-Ende, wenn kein
  //                                weiterer list-Blade folgt).
  async _appendBladeAtUrl({ stackId, url, forceNew = false,
                            sourceListCard = null, mode = "append_to_stack" }) {
    if (!forceNew) {
      const existing = this.cardForUuid(stackId)
      if (existing) {
        this._expandCard(existing)
        this._scrollCardIntoFocus(existing)
        return
      }
    }
    const res = await fetch(url, { headers: { "Accept": "text/html" } })
    if (!res.ok) {
      console.warn("blade fetch failed", url, res.status)
      this._showBladeError(`Blade konnte nicht geladen werden (${res.status})`)
      return
    }
    const html = await res.text()
    const { nodes, card } = this._parseCardHtml(html)   // #621
    if (!card) return
    this.containerTarget.querySelectorAll(":scope > p").forEach(el => el.remove())

    if (sourceListCard && mode === "replace_substack") {
      // #593: Abbruch, wenn der Nutzer dirty Entwürfe nicht verwerfen will.
      if (!this._replaceSubStackAfter(sourceListCard)) return
    }
    if (sourceListCard && (mode === "replace_substack" || mode === "append_to_substack")) {
      nodes.forEach(n => this._insertAtEndOfSubStack(sourceListCard, n))
    } else {
      nodes.forEach(n => this.containerTarget.appendChild(n))
    }

    this._uniquifyCardId(card)
    this._applySavedWidth(card)   // #601: VOR dem Scroll, sonst Default-Breite
    this.restickify()
    requestAnimationFrame(() => {
      this._scrollCardIntoFocus(card)
    })
  }

  // #237: Mobile-Pfad nutzt scroll-snap (snap-align:start auf der Card);
  // ein `scrollIntoView({inline:'end'})` snapped der Browser sofort
  // zurueck auf den naechsten Snap-Point — d.h. die neue Card bleibt
  // offscreen, der User muss von Hand swipen. Auf Mobile darum
  // explizit `container.scrollTo(card.offsetLeft)`, das mit der
  // snap-align harmoniert. Desktop bleibt unveraendert.
  // _scrollCardIntoFocus liegt in BladeStackScrollMixin (#529).

  // Sub-Stack-Range: gibt zurueck, was zwischen sourceListCard
  // (exklusiv) und dem naechsten list-Blade (exklusiv) liegt. Wenn kein
  // weiterer list-Blade folgt: bis Container-Ende.
  _subStackEndElement(sourceListCard) {
    let cur = sourceListCard.nextElementSibling
    while (cur) {
      if (cur.matches?.("article.stack-card[data-uuid^='list:']")) return cur
      cur = cur.nextElementSibling
    }
    return null  // = ans Ende
  }

  // #593: liefert false, wenn der Nutzer das Verwerfen dirty Entwürfe in
  // den zu ersetzenden Cards ablehnt — der Aufrufer bricht dann ab.
  _replaceSubStackAfter(sourceListCard) {
    const endEl = this._subStackEndElement(sourceListCard)
    const doomed = []
    let cur = sourceListCard.nextElementSibling
    while (cur && cur !== endEl) {
      doomed.push(cur)
      cur = cur.nextElementSibling
    }
    if (!this._confirmDiscardDrafts(doomed)) return false
    doomed.forEach(c => c.remove())
    return true
  }

  _insertAtEndOfSubStack(sourceListCard, newCard) {
    const endEl = this._subStackEndElement(sourceListCard)
    if (endEl) {
      this.containerTarget.insertBefore(newCard, endEl)
    } else {
      this.containerTarget.appendChild(newCard)
    }
  }

  // #163 Phase 6a: stellt sicher, dass die HTML-id der Card eindeutig
  // im Dokument ist. Bei Mehrfach-Instanzen desselben Items bekommt die
  // zweite Card `…__2`, die dritte `…__3` usw. data-uuid bleibt
  // unangetastet — der Stack-Param serialisiert beide als gleiche
  // Tokens und der Loader restauriert beide Instanzen.
  _uniquifyCardId(card) {
    const baseId = card.id
    if (!baseId) return
    if (!document.getElementById(baseId) || document.getElementById(baseId) === card) return
    let n = 2
    let candidate = `${baseId}__${n}`
    while (document.getElementById(candidate)) {
      n += 1
      candidate = `${baseId}__${n}`
    }
    card.id = candidate
  }

  // #163 Phase 6a: Spine-Klick toggelt collapse/expand. Eingeklappte
  // Cards zeigen nur den Spine (~28px breit), der Body verschwindet.
  // Listen-Blades nutzen das nach Item-Auswahl als Auto-Collapse;
  // Detail-Blades koennen per Klick eingeklappt werden, um Platz zu
  // schaffen.
  // toggleCollapse, _onCollapseTransitionEnd, _expandCard,
  // _autoCollapseSourceList liegen in BladeStackCollapseMixin
  // (lib/blade_stack_collapse.js, #529) — via Object.assign aufs Prototype
  // gemixt, `blade-stack#toggleCollapse` über die Prototype-Chain.

  // #224 6f-2: Plus-Icon „An Sub-Stack anhaengen". Vorher haengten wir
  // ganz hinten an; jetzt direkt ans Ende des dazugehoerigen Sub-Stacks
  // (also vor dem naechsten list:*-Blade), damit die neue Card im
  // gleichen Kontext wie ihr Listen-Item bleibt. Erlaubt nach wie vor
  // mehrere Instanzen desselben Items im Stack.
  async appendFromList(event) {
    event.preventDefault()
    event.stopPropagation()
    const uuid = event.currentTarget.dataset.targetUuid
    if (!uuid) return
    const sourceListCard = event.target?.closest?.("article.stack-card[data-uuid^='list:']")
    const url = this.cardUrlTemplateValue.replace("UUID", uuid)
    await this._appendBladeAtUrl({
      stackId: uuid, url,
      forceNew:       true,
      sourceListCard,
      mode:           sourceListCard ? "append_to_substack" : "append_to_stack"
    })
    this.pushTrailState()
    this.applyHighlighting()
    this.refreshTrailControls()
    this.syncUrl({ pushHistory: true })
  }

  // #434 (Hans, 2026-06-01): History-Key aus dem ersten Listen-Blade ableiten.
  // Ist das erste Blade eine Liste (list:…), bekommt sie ihren eigenen
  // Verlaufs-Bucket; sonst der Seiten-Default als Fallback.
  _effectiveHistoryKey() {
    const first = this.openUuids()[0]
    if (first && first.startsWith("list:")) return `stack.history.${first}`
    return this._pageHistoryKey || this.historyStorageKeyValue
  }

  // Drawer (stack-history-Controller) liest den Key aus diesem data-Attribut —
  // synchron halten, damit der Verlauf-Drawer denselben Bucket zeigt.
  _syncHistoryKeyAttr() {
    this.element.dataset.bladeStackHistoryStorageKeyValue = this.history?.storageKey || this._effectiveHistoryKey()
  }

  // Nach einem Wechsel des ersten Blades den History-Bucket umstellen. Die
  // Aufrufer haben den ALTEN Trail bereits via snapshotToHistory() (alter
  // Bucket) gesichert, bevor sie den Trail aendern.
  _rekeyHistory() {
    const key = this._effectiveHistoryKey()
    if (this.history?.storageKey === key) return
    this.history = new BladeStackHistory(key)
    this._syncHistoryKeyAttr()
  }

  // Großer Wechsel: aktueller Trail in History, neuer Stack startet
  // mit nur der angeforderten UUID — Trail wird neu initialisiert.
  async replaceStack(uuid) {
    // #593: kompletter Stack-Reset verwirft alle Cards — Entwürfe schützen.
    if (!this._confirmDiscardDrafts(Array.from(this.containerTarget.querySelectorAll(".stack-card")))) return
    this.snapshotToHistory()
    this.trail        = []
    this.currentIndex = -1
    this.containerTarget.innerHTML = ""
    await this.appendCard(uuid)
    this.trail        = [[uuid]]
    this.currentIndex = 0
    this._rekeyHistory()   // neues erstes Blade -> ggf. neuer Verlaufs-Bucket
    this.restickify()
    this.applyHighlighting()
    this.refreshTrailControls()
    this.syncUrl({ pushHistory: true })
  }

  // Stellt einen kompletten Trail wieder her (vom History-Drawer).
  async restoreFromHistory(trail, currentIndex) {
    this.snapshotToHistory()
    this.trail        = trail.map(s => Array.from(s))
    this.currentIndex = Math.max(0, Math.min(currentIndex, trail.length - 1))
    await this.applyTrailState({ pushHistory: true })
    this._rekeyHistory()
    this.refreshTrailControls()
  }

  // restoreLastFromHistoryIfAny, pushTrailState, stepTrail,
  // applyTrailState, refreshTrailControls sind in BladeStackTrailMixin
  // (#378 Phase 9) — via Object.assign auf das Prototype gemixt.

  // ─── DOM-Helpers ────────────────────────────────────────────────

  cardForUuid(uuid) {
    return this.containerTarget.querySelector(`[data-uuid="${uuid}"]`)
  }

  openUuids() {
    return Array.from(this.containerTarget.querySelectorAll("[data-uuid]"))
      .map(el => el.dataset.uuid)
  }

  truncateAfter(anchorCard) {
    let next = anchorCard.nextElementSibling
    while (next) {
      const sib = next.nextElementSibling
      next.remove()
      next = sib
    }
  }

  // appendCard wie früher — fügt zusätzlich nicht in den Trail ein
  // (das macht der Aufrufer via pushTrailState).
  async appendCard(uuid) {
    return this.appendCardBare(uuid)
  }

  // #509 (Hans, 2026-06-04): Aus dem Verlauf-Drawer einen Eintrag ANHÄNGEN
  // (statt den Stack zu ersetzen). Hängt jede Card des Eintrags ans
  // Stack-Ende; schon offene Cards werden übersprungen/fokussiert. Trail +
  // URL werden einmal am Ende aktualisiert.
  async appendStackIds(ids) {
    if (!Array.isArray(ids) || ids.length === 0) return
    let appended = false
    for (const id of ids) {
      if (!id) continue
      const existing = this.cardForUuid(id)
      if (existing) { this._expandCard?.(existing); continue }
      await this.appendCard(id)
      appended = true
    }
    if (appended) {
      this.pushTrailState()
      this.applyHighlighting?.()
      this.refreshTrailControls?.()
      this.syncUrl?.({ pushHistory: true })
    }
  }

  // #362 (Hans, 2026-05-25): Card direkt rechts der gegebenen Quell-
  // Card einfuegen statt am Stack-Ende. Genutzt vom Reference-Blade
  // (refs:ki:* / refs:topic:*), damit die Referenz im Kontext bleibt.
  async appendCardAfter(uuid, sourceCard) {
    const url = this._urlForStackId(uuid) || this.cardUrlTemplateValue.replace("UUID", uuid)
    const res = await fetch(url, { headers: { "Accept": "text/html" } })
    if (!res.ok) { console.warn("blade-stack: fetch failed", res.status); return }
    const html = await res.text()
    const { nodes, card } = this._parseCardHtml(html)   // #621
    if (!card) return
    let ref = sourceCard
    nodes.forEach(n => { ref.insertAdjacentElement("afterend", n); ref = n })
    this._applySavedWidth(card)   // #601
    requestAnimationFrame(() => {
      this._scrollCardIntoFocus(card)
    })
  }

  // Lädt eine bereits geöffnete Card neu vom Server und tauscht sie an
  // gleicher Stelle aus. Brauchen wir z.B. nach `comment_at`: der neue
  // Backlink-Counter am Block soll sofort erscheinen, ohne dass der
  // User die Card schließt und neu öffnet.
  // #360 (Hans, 2026-05-25): _urlForStackId statt cardUrlTemplate, damit
  // Refresh auch fuer Nicht-KI-Typen funktioniert (render:topic:*,
  // refs:*, task:*, …).
  async refreshCard(uuid) {
    const old = this.cardForUuid(uuid)
    if (!old) return
    // #615 (Hans): aktive Suchbegriffe + Scrollposition über den Refresh
    // (z.B. nach einem Highlight) retten. Positionsweise — eine Card kann
    // mehrere Suchschlitze haben (Karten-Suche + Antworten-Thread).
    const searchValues = Array.from(
      old.querySelectorAll('[data-reply-search-target="input"]')).map(i => i.value)
    const savedTop = old.querySelector(".overflow-y-auto")?.scrollTop ?? null
    const url = this._urlForStackId(uuid) || this.cardUrlTemplateValue.replace("UUID", uuid)
    const res = await fetch(url, { headers: { "Accept": "text/html" } })
    if (!res.ok) return
    const html = await res.text()
    const { nodes, card: fresh } = this._parseCardHtml(html)   // #621
    if (!fresh) return
    old.replaceWith(...nodes)
    this._applySavedWidth(fresh)   // #601: gemerkte Breite auch beim Refresh
    const restoreScroll = () => {
      if (savedTop == null) return
      const sc = fresh.querySelector(".overflow-y-auto")
      if (sc) sc.scrollTop = savedTop
    }
    restoreScroll()   // sofort — kein sichtbarer Sprung nach oben
    // Suche erst NACH dem Stimulus-Connect der frischen Card neu anwenden
    // (der input-Event verpuffte sonst vor dem connect) — danach den
    // Scroll erneut setzen, weil das gefilterte Layout anders misst.
    setTimeout(() => {
      const inputs = Array.from(fresh.querySelectorAll('[data-reply-search-target="input"]'))
      let reapplied = false
      searchValues.forEach((v, i) => {
        if (!v || !v.trim() || !inputs[i]) return
        inputs[i].value = v
        inputs[i].dispatchEvent(new Event("input", { bubbles: true }))
        reapplied = true
      })
      if (reapplied) setTimeout(restoreScroll, 220)
    }, 60)
  }

  // #360 (Hans, 2026-05-25): Klick-Action `blade-stack#reloadCard` —
  // findet die enthaltende Card via event.target.closest und ruft
  // refreshCard mit deren UUID auf. Erlaubt einen Reload-Icon in
  // beliebigen Card-Headern (z.B. Render-Blade).
  reloadCard(event) {
    if (event) event.preventDefault()
    const card = event.currentTarget.closest(".stack-card")
    if (!card) return
    const uuid = card.dataset.uuid
    if (!uuid) return
    this.refreshCard(uuid)
  }

  async appendCardBare(uuid) {
    // #352 (Hans, 2026-05-25): _urlForStackId kennt alle Card-Typen
    // (task:, topic:, render:topic:, list:, …). cardUrlTemplate ist
    // nur fuer KnowledgeItem-UUIDs gedacht — fuer alles mit Prefix
    // muss der Typ-Switch greifen, sonst fetched der Append-Pfad
    // /knowledge_items/<prefix:id>/card (404).
    const url = this._urlForStackId(uuid) || this.cardUrlTemplateValue.replace("UUID", uuid)
    const res = await fetch(url, { headers: { "Accept": "text/html" } })
    if (!res.ok) { console.warn("blade-stack: fetch failed", res.status); return }
    const html = await res.text()
    const tpl = document.createElement("template")
    tpl.innerHTML = html.trim()
    // #434 (Hans, 2026-06-01): Listen-Blades (z.B. /tasks/list_card) liefern
    // turbo-cable-stream-source(s) fuer Live-Updates VOR dem <article>. Nicht
    // nur firstElementChild nehmen (das waere der Stream-Source) — alle
    // Top-Level-Knoten uebernehmen und die eigentliche Card herauspicken.
    const nodes = Array.from(tpl.content.children)
    const card  = nodes.find(n => n.classList?.contains("stack-card")) || tpl.content.firstElementChild
    if (!card) return
    // Empty-State-Placeholder ("Eintrag links auswählen →") entfernen,
    // bevor die erste echte Card eingehängt wird — sonst füllt sein
    // m-auto den flex-row-Raum und schiebt die Card nach rechts.
    this.containerTarget.querySelectorAll(":scope > p").forEach(el => el.remove())
    const wasEmpty = this.openUuids().length === 0
    nodes.forEach(n => this.containerTarget.appendChild(n))
    this._applySavedWidth(card)   // #601
    requestAnimationFrame(() => {
      // Erste Card: links anlegen (scrollLeft=0). Folge-Cards: ganz
      // rechts ans Ende scrollen — #202: scrollIntoView trifft wegen
      // Sticky-Positioning oft daneben, direkt scrollWidth ist
      // zuverlaessig.
      if (wasEmpty) {
        this.containerTarget.scrollLeft = 0
      } else {
        this.containerTarget.scrollTo({ left: this.containerTarget.scrollWidth, behavior: "smooth" })
      }
    })
  }

  syncUrl({ pushHistory }) {
    const uuids = this.openUuids()
    const url = new URL(window.location.href)
    if (uuids.length) url.searchParams.set("stack", uuids.join(","))
    else              url.searchParams.delete("stack")
    if (pushHistory) window.history.pushState({}, "", url.toString())
    else             window.history.replaceState({}, "", url.toString())
    // #265: pro Pfad in sessionStorage festhalten — beim Wieder-
    // Aufruf der Seite ohne ?stack=-Param wird der gespeicherte
    // Stand restauriert.
    this._persistSession(uuids)
  }

  // #265: Stable-ID → URL fuer Session-Restore. Spiegel der kind-
  // Switch-Logik in _onAppendEvent, aber rueckwaerts: aus einem
  // im DOM gemerkten data-uuid die Card-URL ableiten.
  _urlForStackId(id) {
    // #564: delegiert an die EINE Routing-Tabelle (lib/blade_stack_routes) —
    // gleiche Quelle wie der Append-Event-Pfad, kein Drift mehr.
    return BladeStackRoutes.urlFor(id, { cardUrlTemplate: this.cardUrlTemplateValue })
  }

  // _sessionKey / _persistSession / _restoreSessionStackIfNeeded /
  // syncFromUrl / snapshotToHistory liegen in BladeStackTrailMixin
  // (#378 Phase 9).

  // #270: pro Card kann der Server via data-focus-after-add="<feld>"
  // einliefern, welches Eingabefeld nach dem Anhaengen den Cursor
  // bekommen soll. Aktuell unterstuetzt: "description" (Task-Description-
  // Textarea). Attribut wird konsumiert (entfernt), damit das nur einmal
  // beim ersten Append triggert.
  _focusAfterAdd(card) {
    const which = card.dataset.focusAfterAdd
    if (!which) return
    card.removeAttribute("data-focus-after-add")
    if (which === "description") {
      // #390 (Hans, 2026-05-31): Cursor ins Task-Beschreibungsfeld nach
      // Quick-Add (Topbar / Dashboard).
      // #445 (Hans, 2026-06-01): Zwei Bugs, die den Cursor stattdessen
      // ins ANTWORT-Feld setzten:
      //   1) Die Card hat ZWEI CM6-Editoren (Beschreibung + Antwort).
      //      `card.querySelector(".cm-editor .cm-content")` war NICHT auf
      //      die Beschreibung gescoped — mountete das Antwort-CM6 zuerst,
      //      traf der Selektor dessen Content-Area → Cursor in der Antwort.
      //      Jetzt scopen wir auf die description-toggle-Section.
      //   2) CM6 mountet asynchron. Ein einzelnes rAF traf das
      //      Beschreibungs-`.cm-content` oft noch nicht → Fallback auf die
      //      (gleich darauf via CM6 versteckte) Textarea, Fokus ging
      //      verloren. Jetzt pollen wir ein paar Frames, bis das
      //      Beschreibungs-CM6 da ist; erst danach Fallback auf die
      //      Textarea (CM6 deaktiviert).
      const section = card.querySelector('section[data-controller~="description-toggle"]') || card
      // Bei vorbelegter Beschreibung startet die Section im Preview-Mode
      // (editBtn sichtbar) → erst in den Edit-Mode schalten. Bei leerer
      // Beschreibung ist sie schon im Edit-Mode (editBtn hidden).
      const editBtn = section.querySelector('[data-description-toggle-target="editBtn"]')
      if (editBtn && !editBtn.classList.contains("hidden")) editBtn.click()

      let tries = 0
      const tryFocus = () => {
        const cm = section.querySelector(".cm-editor .cm-content")
        if (cm) { cm.focus({ preventScroll: true }); return }
        if (tries++ < 12) { requestAnimationFrame(tryFocus); return }
        // CM6 nicht aktiv/aufgetaucht → rohe Textarea (sichtbar) fokussieren.
        const ta = section.querySelector("[data-description-toggle-target='input']")
        if (ta) {
          ta.focus({ preventScroll: true })
          const v = ta.value; ta.value = ""; ta.value = v
        }
      }
      tryFocus()
    } else if (which === "content") {
      // #390 (Hans, 2026-05-28): KI-Beschreibungsfeld (content) im
      // Stack-New-Card-Form. Wenn CM6 aktiv ist, hat der CM6-Editor
      // ein eigenes Content-Area-Element (`.cm-content`) das das
      // Focus-Target ist; sonst die rohe Textarea.
      const cm = card.querySelector(".cm-editor .cm-content")
      const ta = card.querySelector("textarea[name='content']")
      const target = cm || ta
      if (target) {
        target.focus({ preventScroll: true })
        if (ta && !cm) {
          const v = ta.value
          ta.value = ""
          ta.value = v
        }
      }
    } else if (which === "content_edit") {
      // #606 (Hans): Quick-Add-KI — Cursor landete im ANTWORT-Feld. Der
      // alte Pfad (#390 v2) suchte einen description-toggle-Edit-Button,
      // den die KI-Card seit dem Edit-Frame-Refactor nicht mehr hat —
      // gefunden wurde nichts, und der ungescopte CM6-Selector traf das
      // einzige gemountete CM6: das Antwort-Compose. Jetzt nutzen wir
      // denselben Edit-Swap wie der e-Shortcut (laedt den Edit-Frame und
      // fokussiert die Content-Textarea ans Ende).
      const uuid = card.dataset.uuid
      if (uuid && uuid !== "new") this.swapToEditMode(uuid)
    } else if (which === "title") {
      // #739 (Hans): Quick-Add ohne Titel — Cursor ins Titelfeld der frisch
      // angehaengten Card, Platzhalter selektiert, damit man direkt den
      // echten Titel tippt (Task-/Awaiting-Titelfeld heisst <model>[title]).
      const tf = card.querySelector(
        'textarea[name$="[title]"], input[name$="[title]"], textarea[name="title"], input[name="title"]'
      )
      if (tf) {
        tf.focus({ preventScroll: true })
        if (typeof tf.select === "function") tf.select()
      }
    }
  }

  restickify(widthsHint = null) {
    // #224 6f-4 v2: Auf Mobile uebernimmt native CSS scroll-snap das
    // Layout — wir setzen nur data-mobile auf dem Container, CSS macht
    // den Rest. Auf Desktop bleibt das sticky-Stapel-Modell.
    if (this._mediaMobile?.matches) {
      this._applyMobileLayout()
      return
    }
    const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
    if (cards.length === 0) return
    const step  = this.constructor.SPINE_STEP
    const total = cards.length
    // #224 (2026-05-19): cardWidth pro Card, nicht einmal aus cards[0].
    // #277 follow-up: optional widthsHint vom Caller, damit toggleCollapse
    // die Breiten VOR dem dataset-flip einliest. Sonst kommt der forced
    // reflow nach dem CSS-State-Change, und das committet den Endwert ins
    // Layout — die Breiten-Transition fuer die kollabierende Card wird
    // dabei verschluckt.
    // #281 follow-up (Hans, 2026-05-24): wenn das Spine-Stapel-Modell
    // dafuer sorgt, dass die LETZTE Card nach rechts ueber den Container
    // hinausragt, wird sie geclippt — der User sieht nur noch den Spine.
    // Wir clampen sticky-left NUR auf der letzten Card so, dass sie
    // noch ins Viewport passt (max 0..cw-cardWidth). Andere Cards
    // behalten den natuerlichen i*step-Offset, damit der Spine-Stapel
    // links sauber bleibt.
    const cw = this.containerTarget.clientWidth
    cards.forEach((card, i) => {
      const cardWidth = (widthsHint && widthsHint[i] != null)
        ? widthsHint[i]
        : card.getBoundingClientRect().width
      const isLast = i === total - 1
      const naturalLeft = i * step
      const stickyLeft = isLast
        ? Math.min(naturalLeft, Math.max(0, cw - cardWidth))
        : naturalLeft
      card.style.position = "sticky"
      card.style.left     = `${stickyLeft}px`
      card.style.right    = `${(total - i) * step - cardWidth}px`
      card.style.zIndex   = String(i)
    })
  }

  // #803: _applyMobileLayout -> BladeStackMobileMixin (lib/blade_stack_mobile.js)


  applyHighlighting() {
    const open = new Set(this.openUuids())
    this.containerTarget.querySelectorAll(".wikilink").forEach(a => {
      if (open.has(a.dataset.targetUuid)) a.classList.add("wikilink-open")
      else                                a.classList.remove("wikilink-open")
    })
    // Backlink-Counter highlighten, wenn mindestens eine seiner Quellen
    // gerade im Stack offen ist. Plus den umschließenden Block dezent
    // unterlegen — visuell klar, welcher Absatz die offene Card adressiert.
    this.containerTarget.querySelectorAll(".backlink-indicator[data-source-uuids]").forEach(el => {
      const sources = el.dataset.sourceUuids.split(",").filter(Boolean)
      const anyOpen = sources.some(u => open.has(u))
      el.classList.toggle("backlink-indicator-open", anyOpen)
      const block = el.closest("p[id], li[id], blockquote[id]")
      if (block) block.classList.toggle("para-backlinked-open", anyOpen)
    })
  }

  // snapshotToHistory wanderte mit ins BladeStackTrailMixin (#378 Phase 9).

  // #163 Phase 3: Listen-Kollaps. Wenn eine neue Detail-Blade in den
  // Stack appended wird, soll die Wissens-Liste (links) automatisch
  // auf den Streifen kollabieren — sonst frisst sie auf schmalen
  // Viewports viel Platz, der besser fuer die Cards waere. Der
  // list-splitter-Controller liegt auf demselben Root-Element wie wir.
  _collapseListIfExpanded() {
    const splitter = this.application?.getControllerForElementAndIdentifier(this.element, "list-splitter")
    if (!splitter || splitter.isCollapsed?.()) return
    splitter.collapseList()
  }

  // #803: Card-Resize (#163 Phase 6e) -> BladeStackResizeMixin (lib/blade_stack_resize.js)


  // #621: Card-HTML robust parsen — Listen-Blades liefern turbo-cable-
  // stream-sources VOR dem <article> (#434; seit #602 S2b zwei davon bei
  // /tasks/list_card). firstElementChild traf dann den Stream-Tag statt
  // der Card und der Append verpuffte still. Liefert alle Top-Level-
  // Nodes (zum Einfuegen) + die eigentliche Card (fuer Folge-Logik).
  _parseCardHtml(html) {
    const tpl = document.createElement("template")
    tpl.innerHTML = html.trim()
    const nodes = Array.from(tpl.content.children)
    const card  = nodes.find(n => n.classList?.contains("stack-card")) || nodes[0] || null
    return { nodes, card }
  }

  // #613: Fehler beim Blade-Fetch SICHTBAR machen — console.warn ist auf
  // Mobile unsichtbar, der Tipp wirkte wie ein Nichts (Hans-Report).
  // Schlanker Inline-Toast im toast_stack (gleicher Platz wie Server-Toasts).
  _showBladeError(message) {
    const stack = document.getElementById("toast_stack")
    const el = document.createElement("div")
    el.className = "px-3 py-2 rounded border border-rose-200 bg-rose-50 text-rose-800 text-sm shadow"
    el.textContent = message
    ;(stack || document.body).appendChild(el)
    if (!stack) Object.assign(el.style, { position: "fixed", top: "1rem", left: "50%",
                                          transform: "translateX(-50%)", zIndex: 9999 })
    setTimeout(() => el.remove(), 6000)
  }

}

// #378 Phase 8: Spine-Marker-Logic als Mixin angewandt. Methoden sind
// `this`-gebunden, alle Targets + Helpers (setActiveCard etc.) stehen
// weiterhin als this.* zur Verfuegung.
Object.assign(BladeStackController.prototype, BladeStackSpineMixin)

// #378 Phase 9: Trail-/History-/Session-Logic als Mixin. Stimulus
// findet Action-Handler (trailBack, trailForward) ueber den
// Prototype-Chain.
Object.assign(BladeStackController.prototype, BladeStackTrailMixin)

// #529: Scroll-/Geometrie-Logik als Mixin. `this`-gebunden, reines Code-Move.
Object.assign(BladeStackController.prototype, BladeStackScrollMixin)

// #529: Entity-Öffner als Mixin. Stimulus findet die data-action-Handler
// (openSource/openTask/…) über die Prototype-Chain.
Object.assign(BladeStackController.prototype, BladeStackOpenersMixin)

// #529: Collapse/Expand als Mixin. data-action `blade-stack#toggleCollapse`
// über die Prototype-Chain.
Object.assign(BladeStackController.prototype, BladeStackCollapseMixin)

// #529: Tastatur-Logik als Mixin. this.keyHandler -> this.handleKeydown über
// die Prototype-Chain; openShortcutHelp ist data-action.
Object.assign(BladeStackController.prototype, BladeStackKeyboardMixin)

// #803: Edit-Mode-, Mobile-Layout- und Card-Resize-Logik als Mixins
// (Fortführung des #378/#529-Musters).
Object.assign(BladeStackController.prototype, BladeStackEditModeMixin)
Object.assign(BladeStackController.prototype, BladeStackMobileMixin)
Object.assign(BladeStackController.prototype, BladeStackResizeMixin)

export default BladeStackController
