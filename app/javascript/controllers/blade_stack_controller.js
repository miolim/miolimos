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
import { focusTargetAfterClose, endSpacerWidth, standingSpacerWidth, nextShelfStop, prevShelfStop } from "lib/blade_stack_close"
import { stickyOffsets } from "lib/blade_stack_sticky"
import { overhangClips } from "lib/blade_stack_overhang"
// #1648 (Hans): Auch der Wikilink-Klick fragt die Oeffnungsart — Umschalt
// zeigt dasselbe Menue wie an allen anderen Klickwegen (#1642).
import { oeffnungsart } from "lib/blade_open_menu"
// #1677 (aus immoOS #1665): Die offene Hilfe-Card folgt dem Reiter der Karte, zu
// der sie gehört. Die Entscheidung steht in lib/help_tab — hier das Verdrahten.
import { offenerReiter, hilfeBasis, hilfeTauschZiel } from "lib/help_tab"

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
    // #1573: Der Server hat den Stack aus dem Snapshot wiederhergestellt
    // (Dashboard ohne ?stack=, #1066) — die URL zieht dann sofort nach.
    serverRestored:    { type: Boolean, default: false },
    // #1582: Startseiten-Vorliebe „leerer Stack" — nichts wiederherstellen.
    startEmpty:        { type: Boolean, default: false },
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
    // #320 (Hans): Mehrfach-Instanzen markieren — Counter-Badge auf jedem
    // Spine, dessen data-uuid ≥2x im Stack vorkommt.
    this._refreshInstanceCounters()

    // Wenn die Page ohne Stack-Param aufgerufen wurde (z.B. via
    // Sidebar-Klick auf "Wissen"): den letzten Eintrag aus der
    // localStorage-History wiederherstellen, damit der User dort
    // weiterarbeiten kann, wo er aufgehört hat.
    //
    // #1648 (aus immoOS #1645 uebernommen): Bei `?start=empty` (#1582) gilt
    // das NICHT. Der gemerkte Stapel kommt aus zwei Quellen; die #1582-Sperre
    // sass nur am Session-Restore weiter unten. Dieser Weg hier fragte nur
    // „steht gar keine Card da?" — und beim leeren Start steht eben keine.
    // Dadurch kam die zuletzt offene Card zurueck und schrieb sich per
    // syncUrl sogar in die Adresszeile (`?start=empty&stack=…`).
    if (initial.length === 0 && !this.startEmptyValue) {
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
      // #1091 (Hans): „Durch das blosse Schliessen einer Card soll diese
      // nicht den Fokus bekommen." Der pointerdown auf einem Schliessen-
      // Control (Spine-Kreuz, Spine-Top-Hover-X, Toolbar-X, Close-Menue)
      // hat sonst die Card erst aktiviert und _closeCardElements sah sie
      // als „hatte Focus" — der Focus wanderte dann weg vom eigentlich
      // fokussierten Blade.
      if (e.target.closest?.('[data-action*="blade-stack#closeCard"]')) return
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
    // #1677 (aus immoOS #1665): Reiterwechsel in irgendeiner Card — die offene
    // Hilfe dazu zieht nach. Am Container, damit auch nachgeladene Cards erfasst sind.
    this._hilfeReiterHandler = (e) => this._hilfeFolgtReiter(e)
    this.containerTarget.addEventListener("simple-tabs:gewechselt", this._hilfeReiterHandler)
    // Initial-Markierung: letzte Card im Stack, falls eine offen ist.
    // #284 v2: nach Reload die aeusserst rechte Card sticky-aware ins
    // Viewport scrollen. v1 nutzte scrollIntoView({inline:"nearest"}) —
    // bei Sticky-Positionierung glaubt der Browser, die Card sei schon
    // sichtbar (rendered position via sticky-Offset), und scrollt nicht.
    // Wir berechnen den Ziel-scrollLeft per kumulativer Card-Breite
    // (Content-Koordinaten, NICHT getBCR der gestickyten Cards) und
    // setzen scrollLeft direkt — kein Smooth, soll beim Reload im
    // richtigen Frame stehen.
    const last = this.containerTarget.querySelector(".stack-card:last-of-type")
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

    // #1228: Welche Card wie weit ueber ihre Nachfolgerin ragt, aendert
    // sich waehrend des Scrollens laufend (Cards kleben an und loesen
    // sich wieder) — pro Frame einmal nachziehen, nicht pro Scroll-Event.
    this._onContainerScroll = () => {
      if (this._clipFrame) return
      this._clipFrame = requestAnimationFrame(() => {
        this._clipFrame = null
        this._clipOverhang()
      })
    }
    this.containerTarget.addEventListener("scroll", this._onContainerScroll, { passive: true })

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
        // #320: Append-Pfad — Mehrfach-Instanzen-Counter neu rechnen.
        this._refreshInstanceCounters()
        // #1091 v4: restickify synchronisiert auch den End-Spacer — eine
        // neue Card fuellt zuerst den End-Freiraum, BEVOR die Scroll-
        // Logik unten zur Card scrollt.
        this.restickify()
        this.applyHighlighting()
        // #1198: per Turbo-Stream appendete Cards (Quick-Create, Server-
        // Streams) als Trail-Schritt erfassen — sonst kann der Back-Pfeil
        // sie nicht zurücknehmen. NICHT während applyTrailState pushen
        // (Back/Forward baut Cards selbst um und würde sich sonst den
        // eigenen Forward-Zweig zerstören); pushTrailState dedupliziert
        // identische Kompositionen (kein Doppel-Push mit den Openern).
        // #1283: Beim Card-Refresh ist die Komposition unveraendert — kein
        // Trail-Schritt, kein Fokuswechsel, kein Scroll. Das Layout oben
        // (Sticky, Counter, Resize-Handle) braucht die frische Card
        // trotzdem, deshalb steht der Ausstieg erst hier.
        if (this._refreshingCard) return
        if (this._applyingTrail) this.syncUrl({ pushHistory: false })
        else                     this.pushTrailState()
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

    // #1167: Beim Initial-Load werden Cards gemessen, BEVOR ihre Turbo-
    // Frames Inhalt haben (Breite ~0) — die Letzte-Card-Klemmung und die
    // Sticky-Rights rechneten dann mit Phantombreiten und blieben so
    // stehen (live beobachtet: letzte Card mit left=896px bei 706px
    // Container). Nach jedem Frame-Load im Stack das Layout nachziehen.
    this._onFrameLoad = (e) => {
      if (this.containerTarget.contains(e.target)) this.restickify()
    }
    document.addEventListener("turbo:frame-load", this._onFrameLoad)

    // #1487 (Hans): „Ein Streifen des Inhaltsbereiches bleibt rechts
    // neben dem Spine stehen; die Spines der folgenden Cards verschwinden
    // dahinter."
    //
    // Die Sticky-Rechnung merkt sich die BREITE jeder Card
    // (`right = Stapel - Breite`). Aendert sich die Breite spaeter, ohne
    // dass neu gerechnet wird, dockt die Card um genau die Differenz zu
    // weit links an — und weil die letzte Card den hoechsten z-Index hat,
    // deckt ihr sichtbarer Rest die nachrueckenden Spines zu.
    //
    // Genau das passiert beim Ziehen am Breiten-Griff: `.stack-card` hat
    // eine 220ms-Transition auf `width` (#224, Collapse-Animation). Wer
    // unmittelbar nach dem Setzen misst, bekommt die ALTE Breite. Live
    // nachgemessen: Card auf 1126px gezogen, restickify mass 576px —
    // 551px Inhalt blieben neben dem Spine stehen.
    //
    // Statt an jeder Stelle, die Breiten anfasst, den richtigen Zeitpunkt
    // zu erraten, hoert der Beobachter zu, WANN eine Breite sich
    // tatsaechlich geaendert hat. Das deckt Ziehen, Transition-Ende,
    // nachgeladene Inhalte und alles ab, was spaeter dazukommt.
    // restickify aendert keine Breiten (nur left/right/z-Index/clip),
    // also gibt es keine Rueckkopplung.
    if (typeof ResizeObserver !== "undefined") {
      this._breitenBeobachter = new ResizeObserver(() => {
        if (this._breitenRaf) return
        this._breitenRaf = requestAnimationFrame(() => {
          this._breitenRaf = null
          this.restickify()
        })
      })
      this._beobachteBreiten()
    }

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
      // #1091 v3b: Der End-Spacer ist ein reines Client-Element — idiomorph
      // wirft ihn beim Page-Morph raus, weil er im Server-HTML nicht
      // vorkommt. Breite merken und unten wieder aufbauen, sonst klemmt
      // der scrollLeft-Restore (scrollWidth ist ohne Spacer kleiner) und
      // der Stack rutscht bei jedem Live-Update nach rechts — genau der
      // Effekt, den der Spacer verhindern soll.
      this._morphSpacerW = this._endSpacerWidthNow()
    }
    this._onAfterRender  = () => {
      if (!this._morphing) return
      this._morphing = false
      // nach dem DOM-Patch: Sticky-Spine + Highlighting + In-Stack-Marker
      // neu berechnen (Card-Anzahl bleibt gleich, aber Inhalte/Hoehen
      // koennen sich geaendert haben).
      this.restickify()
      this.applyHighlighting()
      // #1091 v3b: Spacer VOR dem Scroll-Restore wiederherstellen.
      // v4: restickify oben hat ihn schon auf max(stehend, aktuell)
      // gesetzt — aber mit dem u.U. schon geklemmten scrollLeft; die
      // gemerkte Vor-Morph-Breite gewinnt, wenn sie groesser ist.
      if (this._morphSpacerW > 0 && this.hasContainerTarget && !this._mediaMobile?.matches) {
        this._setEndSpacerWidth(Math.max(this._morphSpacerW, this._endSpacerWidthNow()))
      }
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

    // #163 Phase 4: Bedienelemente, die an den Stapel anhaengen, sollen NUR
    // sichtbar sein, wenn diese Seite einen Blade-Stack hat. Body-Klasse
    // toggled die CSS-Sichtbarkeit — seit #1509 nur noch fuer .topbar-trail
    // (das Sidebar-Plus, das hier ebenfalls dranhing, ist entfallen; die
    // Zeilen der Seitenleiste brauchen kein Gate, siehe stackVorhanden im
    // blade-link-Controller).
    document.body.classList.add("has-blade-stack")

    // #163 Phase 4: Sidebar (separater DOM-Teilbaum, kein Stimulus-
    // Ancestor des blade-stack) dispatcht globale Custom-Events; wir
    // hoeren auf window und routen sie ins normale _appendBladeAtUrl.
    // Erwartetes detail-Shape: { kind: "topic"|"task"|"source", id: String }.
    this._onAppendEvent = async (e) => {
      const { kind, id, sourceListId, anchor, mode: explicitMode, oeffnen, quelleId } = e.detail || {}
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
      // #1067 (Hans, 2026-07-20): Ist der Eintrag schon als Card offen (= rot
      // markiert), zur Card springen statt eine zweite anzuhaengen. Vorher
      // haing das an `fromList`, und das ist nur wahr, wenn der Klick INNERHALB
      // einer `list:`-Card passiert (blade_link_controller: closest
      // article.stack-card[data-uuid^='list:']). Zeilen in einer normalen Card
      // — Rechnungen an einer Person, Aufgaben an einem Thema — hatten also
      // forceNew und oeffneten die Card jedes Mal erneut. Ausnahme bleibt das
      // Plus-Icon: `append_to_substack` heisst ausdruecklich "noch eine".
      const alreadyOpen = !!this.cardForUuid(stackId)

      // #1509 (aus immoos #1348): Ist eine Oeffnungsart angegeben und die
      // aufrufende Card bekannt, entscheidet der KLICK, wo die neue Card
      // landet. Ist sie schon offen, sticht das Springen — egal was
      // gedrueckt war; sonst haette man zwei Karten desselben Dinges.
      // #1509 Nachtrag (Hans): Ein Klick aus der SEITENLEISTE hat keine
      // aufrufende Card — dort gibt es keine. Damit die Modifier auch von
      // dort etwas heissen, tritt die AKTIVE Card an ihre Stelle: „rechts
      // daneben" ist dann rechts neben der Card, auf die man gerade schaut.
      // Nur fuer die drei Modifier-Arten; „ersetzen" ohne aufrufende Card
      // bleibt der gewachsene Anhaengen-Weg (sonst raeumte ein Klick den
      // halben Stapel ab, ohne dass jemand darum gebeten hat).
      const quelle = (quelleId ? document.getElementById(quelleId) : null) ||
                     (oeffnen && oeffnen !== "ersetzen" ? this.activeCard() : null)
      if (oeffnen && quelle && !alreadyOpen) {
        const fertig = await this._oeffneNeben(stackId, url, quelle, oeffnen)
        if (fertig) {
          // #1566 R3 (immoOS): Der Anker gilt auch auf diesem Weg. Bisher
          // wertete ihn nur der Anhängen-Zweig unten aus — ein Klick aus einer
          // Card (der Normalfall seit #1348) öffnete die Ziel-Card, sprang aber
          // nicht zur Stelle. Aufgefallen am Klick auf eine Zuordnungsregel in
          // der Umsatz-Card: Das Mietverhältnis ging auf, der Reiter nicht.
          if (anchor) {
            const card = this.cardForUuid(stackId)
            if (card) {
              this.setActiveCard(card)
              this.scrollToAnchorInCard(card, anchor)
            }
          }
          this.pushTrailState(); this.syncUrl({ pushHistory: false })
        }
        return
      }

      await this._appendBladeAtUrl({
        stackId, url,
        forceNew:       mode === "append_to_substack" || (!fromList && !alreadyOpen),
        sourceListCard,
        mode
      })
      if (anchor) {
        const card = this.cardForUuid(stackId)
        if (card) {
          // #218: collapsed Card erst aufklappen, sonst wird
          // scrollToAnchorInCard ins Leere zielen.
          this._expandCard(card)
          // #1566 R4 (immoOS): Hier stand zusätzlich `card.scrollIntoView` —
          // nicht sticky-bewusst, es überstimmte den Fokus-Scroll aus
          // _appendBladeAtUrl. Und die Card wurde nicht aktiv gesetzt: Bei einer
          // schon offenen Ziel-Card blieb der Fokus beim Aufrufer. Jetzt wie
          // _springeZu (#1348).
          this.setActiveCard(card)
          this.scrollToAnchorInCard(card, anchor)
        }
      }
      // #224 6f-1: kein Auto-Collapse mehr — Listen-Blade bleibt offen,
      // siehe `_autoCollapseSourceList`. sourceListId beeinflusst nur
      // noch die Append-vs.-Focus-Heuristik oben.
      // #1198: auch dieser Append-Pfad (Sidebar-Plus, Nav-Klick, globales
      // Event) ist ein Trail-Schritt — sonst kann der Back-Pfeil ihn nicht
      // zurücknehmen. pushTrailState dedupliziert, falls der Mutation-
      // Observer denselben Stand schon erfasst hat.
      this.pushTrailState()
      this.syncUrl({ pushHistory: true })
    }
    window.addEventListener("blade-stack:append", this._onAppendEvent)

    // #1674 (aus immoOS #1097 uebernommen): Eine Card kann ihre Breite selbst
    // aendern (dort: Listen-Card, die auf Tabelle umschaltet). Der Stack rechnet
    // die Position jeder Card aus ihrer GEMESSENEN Breite — ohne Neuberechnung
    // ueberlappen die Cards oder die Spines verrutschen. Statt restickify() von
    // aussen aufzurufen (der Aufrufer muesste den Controller finden) ein
    // Signal, das jeder senden kann:
    //   window.dispatchEvent(new CustomEvent("blade-stack:relayout"))
    this._onRelayout = () => this.restickify()
    window.addEventListener("blade-stack:relayout", this._onRelayout)
    // #1509 (Hans): „UMSCHALT und ALT-UMSCHALT sind auch Modifier. Bei der
    // Benutzung wird aber an einigen Stellen Text in der Card selektiert.
    // Wenn dann die neue Card geoeffnet wurde, wird die Selektion auf deren
    // Text ausgedehnt. Das ist sehr irritierend."
    //
    // Das Auswaehlen passiert beim MOUSEDOWN, nicht beim Klick — ein
    // `preventDefault` im Klick-Handler kommt also zu spaet. Deshalb hier,
    // eine Ebene frueher.
    //
    // Selektiv, wie gewuenscht: In Eingabefeldern und editierbarem Text
    // bleibt Umschalt+Klick, was es ist — die uebliche Art, eine Auswahl
    // aufzuziehen. Nur auf einer anklickbaren Card-Zeile, wo Umschalt der
    // Modifier fuer „rechts daneben oeffnen" ist, wird die Auswahl
    // unterdrueckt. Eine andere Taste zu nehmen ist damit nicht noetig.
    this._keineAuswahlBeiModifier = (event) => {
      if (!event.shiftKey) return               // nur Umschalt zieht auf
      if (event.button !== 0) return            // nur die linke Taste
      const ziel = event.target
      if (!ziel?.closest) return
      // In Textfeldern gehoert das Aufziehen dem Nutzer.
      if (ziel.closest("input, textarea, select, [contenteditable=''], [contenteditable='true']")) return
      // Nur dort eingreifen, wo Umschalt ueberhaupt eine Bedeutung hat.
      // #1576: Listenzeilen, die ueber openFromList / openDocument laufen, tragen
      // dieselbe Regel, aber keinen blade-link-Controller — dort hat Umschalt+
      // Klick bisher Text markiert.
      if (!ziel.closest("[data-controller~='blade-link'], [data-action*='blade-stack#openFromList'], [data-action*='blade-stack#openDocument']")) return
      event.preventDefault()
    }
    document.addEventListener("mousedown", this._keineAuswahlBeiModifier, true)

    // #1198: Topbar-Pfeile (Schritt zurück/vor) liegen außerhalb des
    // Stimulus-Scopes — sie feuern ein globales Event (Muster wie
    // blade-stack:append), das hier in die Trail-Mechanik routet.
    this._onTrailNav = (e) => {
      const delta = e.detail?.delta
      if (delta === -1 || delta === 1) this.stepTrail(delta)
    }
    window.addEventListener("blade-stack:trail", this._onTrailNav)

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
    } else if (this.serverRestoredValue && this.openUuids().length) {
      // #1573 (Hans): „im URL-Feld steht nur os.miolim.de/dashboard, und
      // dann kommt irgendwann die Ergaenzung um die Cards." Seit #1066
      // rendert der Server den letzten Stack, ohne dass die URL ihn nennt;
      // geschrieben wurde sie erst bei der naechsten Stack-Aenderung. Jetzt
      // sofort (replace, kein neuer History-Eintrag) — und KEIN Session-
      // Restore: Die Cards stehen schon, ein aelterer Stand aus dem
      // sessionStorage haengte sonst Karten an, die der Snapshot nicht hat.
      this.syncUrl({ pushHistory: false })
    } else if (this.startEmptyValue) {
      // #1582 (Hans): „mit einem leeren Stack, also ohne voreingestellte
      // Card starten" — dann auch keinen gemerkten Stand nachladen.
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
    if (this._hilfeReiterHandler) {
      this.containerTarget.removeEventListener("simple-tabs:gewechselt", this._hilfeReiterHandler)
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
    if (this._onContainerScroll) {
      this.containerTarget.removeEventListener("scroll", this._onContainerScroll)
      if (this._clipFrame) { cancelAnimationFrame(this._clipFrame); this._clipFrame = null }
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
    if (this._onFrameLoad) document.removeEventListener("turbo:frame-load", this._onFrameLoad)
    // #1487
    if (this._breitenRaf) { cancelAnimationFrame(this._breitenRaf); this._breitenRaf = null }
    this._breitenBeobachter?.disconnect()
    this._dismissCloseMenu()
    // #1496 (aus immoos #1302): NUR entfernen, wenn wirklich kein
    // Container mehr dasteht. Trennt sich eine Alt-Instanz, nachdem die
    // lebende sich verbunden hat, riss das bisher den Merker weg — und mit
    // ihm die Klick-Pfade, die daran hingen.
    if (!document.querySelector('[data-blade-stack-target="container"]')) {
      document.body.classList.remove("has-blade-stack")
    }
    if (this._onAppendEvent) window.removeEventListener("blade-stack:append", this._onAppendEvent)
    if (this._onRelayout) window.removeEventListener("blade-stack:relayout", this._onRelayout)
    if (this._keineAuswahlBeiModifier) {
      document.removeEventListener("mousedown", this._keineAuswahlBeiModifier, true)
    }
    if (this._onTrailNav)    window.removeEventListener("blade-stack:trail", this._onTrailNav)
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
    // #1091 v2: :last-of-type statt :last-child — der End-Spacer (div)
    // kann das letzte Kind des Containers sein, die Cards sind <article>.
    return this.containerTarget.querySelector('.stack-card[data-active="true"]') ||
           this.containerTarget.querySelector(".stack-card:last-of-type")
  }

  // #1486 (Hans): „Wenn ich per Tastatur zu einer anderen Card navigiere,
  // wird der Vertikal-Scroll-Fokus nicht mitgenommen."
  //
  // Welche Card die Pfeiltasten scrollen, entscheidet nicht `data-active`,
  // sondern der DOM-Fokus: Der Browser scrollt den naechsten scrollbaren
  // Vorfahren des fokussierten Elements. Ein Mausklick setzt diesen Fokus
  // nebenbei mit — deshalb funktionierte ↑/↓ nach dem Klicken und nach
  // Strg+Alt+Pfeil nicht. Der Fokus blieb auf der alten Card stehen.
  //
  // Fokussiert wird der Inhaltsbereich SELBST, nicht das erste fokussier-
  // bare Element darin: Sonst haengt das Scrollen davon ab, ob die Card
  // zufaellig einen Link enthaelt, und der Sprung dorthin scrollte die
  // Card auch noch ungefragt an eine andere Stelle.
  //
  // Absichtlich NICHT in setActiveCard: Das laeuft auch beim Scroll-Sync
  // auf dem Telefon (bei jedem Wisch) und beim Nachrutschen nach einem
  // Close. Fokus wandert nur, wenn jemand die Card ausdruecklich wechselt.
  _focusCardBody(card) {
    if (!card) return
    const box = card.querySelector(":scope > .overflow-y-auto")
    const ziel = box || card
    // tabindex="-1": programmatisch fokussierbar, aber NICHT in der
    // Tab-Reihenfolge — sonst laege zwischen je zwei Bedienelementen ein
    // zusaetzlicher Halt, den vorher niemand hatte.
    if (!ziel.hasAttribute("tabindex")) ziel.setAttribute("tabindex", "-1")
    // preventScroll: Das Positionieren der Card macht scrollCardIntoView
    // eine Zeile weiter. Ohne die Bremse zoege der Fokus die Card selbst
    // noch einmal ins Bild und beide Bewegungen kaempften gegeneinander.
    ziel.focus({ preventScroll: true })
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
    // #1348: Cmd/Strg gehoert dem Browser („in neuem Tab öffnen").
    if (event.metaKey || event.ctrlKey) return
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

    // #1674 (aus immoOS #1348 uebernommen; Hans: „a" — ueberall dieselbe Regel):
    // Auch der Wikilink folgt der EINEN Oeffnungsregel (lib/blade_open_menu) —
    // schlichter Klick ersetzt alles rechts der aufrufenden Card, Umschalt
    // fragt per Menue (ans Ende · rechts · links · ersetzen), Cmd/Strg gehoert
    // dem Browser. Vorher hing die Ziel-Card am Stack-ENDE (#312), also weit
    // weg vom Kontext — und anders als an jedem anderen Klickweg.
    const sourceCard = link.closest(".stack-card")
    if (sourceCard && !uuid.startsWith("refs:")) {
      let url = this._urlForStackId(uuid) || this.cardUrlTemplateValue.replace("UUID", uuid)
      // #1393 R3 (Hans): Ein Verweis darf sagen, WOVON aus er kommt — die
      // Konto-Card zeigt dann einen Ausschnitt um diesen Umsatz statt der
      // letzten 50 (in denen ein aelterer gar nicht vorkommt).
      if (link.dataset.targetQuery) {
        url += (url.includes("?") ? "&" : "?") + link.dataset.targetQuery
      }
      // #1348: dieselbe Belegung wie im blade-link-Controller. immoOS #1643
      // (aus miolimOS #1642): das ist jetzt das Umschalt-Menue — ein Abbruch
      // (Escape, Klick daneben) oeffnet nichts.
      const art = await oeffnungsart(event)
      if (!art || art === "browser") return
      if (await this._oeffneNeben(uuid, url, sourceCard, art)) {
        this.pushTrailState()
        this._collapseListIfExpanded()
        if (blockAnchor) this._springeZu(uuid, blockAnchor)
        this.applyHighlighting?.()
        this.refreshTrailControls?.()
        this.syncUrl?.({ pushHistory: true })
      }
      return
    }

    // #362 (Hans, 2026-05-25): Reference-Blade (refs:ki:* / refs:topic:*)
    // wird DIREKT RECHTS der aufrufenden Card geoeffnet — sonst landet
    // die Referenz weit weg vom Kontext.
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

    // #1674 (Hans, 19.09.2026: „a" — ueberall dieselbe Regel): Hier stand #1648
    // mit einem zweiten Umschalt-Menue und dem Satz „OHNE Umschalt bleibt es
    // beim Anhaengen ans Ende". Beides entfaellt: Der Weg oben (#1348, aus dem
    // immoOS-Fork uebernommen) faengt jeden Wikilink AUS einer Card bereits ab,
    // samt Menue. Hierher kommt nur noch ein Wikilink OHNE aufrufende Card;
    // dort gibt es keinen Anker fuer „links/rechts daneben".

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
      // #1091 v4: NATUERLICHES Content-Ende, nicht scrollWidth — das
      // enthaelt jetzt den stehenden Overscroll-Spacer; scrollWidth
      // wuerde die neue Card links gepinnt in der Leere abstellen.
      // #1509 (Hinweis von immoos_builder, dort #1503): NICHT ans rechnerische
      // Ende springen. Das ist nur so lange dasselbe wie „zur neuen Card",
      // wie dieses Ende RECHTS der aktuellen Position liegt. Steht man im
      // Freiraum dahinter (#1091 v4), ist es KLEINER — der Stapel springt
      // zurueck und klappt die weggescrollten Ruecken wieder auf. Gemessen:
      // 548 → 394. `_scrollCardIntoFocus` scrollt nur so weit wie noetig.
      if (wasEmpty) this.containerTarget.scrollLeft = 0
      else this._scrollCardIntoFocus(card)
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
    // #1631 (aus immoos #1481 R2 uebernommen). Hans dort: „Bitte
    // generalisieren: Einfach immer anzeigen. Ggf. entsteht dann ein leerer
    // Stack, aber das schadet ja auch nicht. Klick in die Sidebar öffnet ja
    // wieder die erste Card." — und: „Bitte in den Infos für miolim
    // festhalten, dass es dort auch so umgesetzt wird."
    //
    // Beide Einträge sind deshalb immer freigegeben — auch an der ersten Karte
    // (leert den Stapel) und an der letzten (wirkt wie „Diese Karte
    // schließen"). Die mit #1496 übernommene Sperre ist bewusst entfallen.
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
    addItem(window.t("blade_stack.close_menu_this"), true, () => this._closeCardElement(card))
    addItem(window.t("blade_stack.close_menu_right_of"), true, () => this._closeCardsFrom(card))
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
  // rechts davon schließen") — EIN Entwurfs-Confirm über alle Cards.
  // #1091 (Hans, 2026-07-22): Focus wandert NUR, wenn die geschlossene
  // Card ihn hatte — dann bevorzugt nach RECHTS (Regel aus #358 gedreht),
  // sonst nach links. Schliesst man eine Hintergrund-Card, bleibt der
  // Focus wo er ist. Ausserdem bleibt die Scrollposition erhalten: die
  // Cards links der geschlossenen ruecken nicht nach, die rechten fuellen
  // den Platz nach rechts auf (Flex-Reflow erledigt das von selbst).
  _closeCardElement(card) {
    this._closeCardElements([card])
  }

  _closeCardElements(cards) {
    cards = cards.filter(c => c && !c.classList.contains("is-closing"))  // Doppelklick-Schutz
    if (!cards.length) return
    if (!this._confirmDiscardDrafts(cards)) return
    // #1091: Nachfolger vorab bestimmen — null heisst „Focus bleibt".
    const allCards  = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
    const active    = this.containerTarget.querySelector('.stack-card[data-active="true"]')
    const focusNext = focusTargetAfterClose(allCards, cards, active)
    // #1091: Scrollposition festhalten. Waehrend die Cards auf Breite 0
    // gleiten schrumpft scrollWidth; der Browser klemmt scrollLeft dabei
    // nach und alles links wuerde nach rechts rutschen.
    const keepScrollLeft = this.containerTarget.scrollLeft

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
    // #1091 v2 (Hans): End-Spacer VOR der Animation auf die End-Groesse
    // aufziehen. Reicht die verbleibende Card-Breite nicht mehr bis an
    // den rechten Viewport-Rand, wuerde der Browser scrollLeft nach-
    // klemmen und die links gestapelten Spines fuehren wieder aus. Mit
    // dem Platzhalter bleibt die Scrollbreite waehrend der gesamten
    // Transition gueltig: links steht alles fest, die rechten Cards
    // ruecken nach links auf, rechts entsteht Freiraum. #1091 v3: der
    // Freiraum bleibt begehbar (rein/raus scrollen); beim Schliessen
    // waechst er nur (grow-only) — schliesst man Cards von links weg,
    // nimmt er kontinuierlich zu, bis neue Cards ihn wieder fuellen.
    const remaining = allCards.filter(c => !cards.includes(c))
    if (remaining.length) {
      const closingW = cards.reduce((sum, c) => sum + c.getBoundingClientRect().width, 0)
      const spacerW  = this._endSpacerWidthNow()
      const needed   = endSpacerWidth({
        scrollLeft:   keepScrollLeft,
        clientWidth:  this.containerTarget.clientWidth,
        contentWidth: this.containerTarget.scrollWidth - spacerW - closingW
      })
      if (needed > spacerW) this._setEndSpacerWidth(needed)
    } else {
      this._endSpacer()?.remove()
    }
    let pending = cards.length
    const finishAll = () => {
      this.containerTarget.scrollLeft = keepScrollLeft
      // #1091 v3: Spacer exakt nachmessen, aber NUR wachsen lassen. Die
      // Vor-Animation-Schaetzung kann um Pixel danebenliegen (Margins,
      // Rundung) — zu klein hiesse Nachklemmen. Ein bestehender
      // groesserer Freiraum bleibt unangetastet; getrimmt wird er nur,
      // wenn neue Cards ihn fuellen (MutationObserver → _syncEndSpacer).
      const spacerW = this._endSpacerWidthNow()
      const needed  = endSpacerWidth({
        scrollLeft:   keepScrollLeft,
        clientWidth:  this.containerTarget.clientWidth,
        contentWidth: this.containerTarget.scrollWidth - spacerW
      })
      if (needed > spacerW) this._setEndSpacerWidth(needed)
      if (focusNext && focusNext.isConnected) {
        this.setActiveCard(focusNext)
        // #1091: nur nachscrollen, wenn der neue Focus sonst nicht
        // sichtbar waere. „nearest" laesst die Scrollposition in Ruhe,
        // solange die Card im Viewport liegt — _scrollCardIntoFocus
        // haette sie stattdessen immer neu ausgerichtet.
        this.scrollCardIntoView(focusNext)
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

  // ─── #1091 v2/v3: End-Spacer (Freiraum rechts nach dem Schliessen) ──
  //
  // Ein unsichtbares Flex-Kind am visuellen Stack-Ende (order:9999,
  // damit spaetere appendChild-Cards im DOM dahinter, visuell aber
  // davor landen). Es haelt die Scrollbreite, damit der Browser nach
  // einem Close scrollLeft nicht nachklemmt — alles links der
  // geschlossenen Card bleibt dadurch stehen. #1091 v3 (Hans): der
  // Freiraum ist begehbar — nach rechts hinein- und herausscrollen ist
  // ausdruecklich erlaubt, es gibt KEINEN Abbau beim Scrollen. Er
  // schrumpft nur, wenn neue Cards angehaengt werden. Die Mathematik
  // liegt als reine Funktion in lib/blade_stack_close.js
  // (endSpacerWidth) und ist dort unit-getestet.

  _endSpacer() {
    return this.containerTarget.querySelector(":scope > .stack-end-spacer")
  }

  _endSpacerWidthNow() {
    const sp = this._endSpacer()
    return sp ? (parseFloat(sp.style.width) || 0) : 0
  }

  _setEndSpacerWidth(width) {
    if (width <= 0) { this._endSpacer()?.remove(); return }
    let sp = this._endSpacer()
    if (!sp) {
      sp = document.createElement("div")
      sp.className = "stack-end-spacer shrink-0 pointer-events-none"
      sp.setAttribute("aria-hidden", "true")
      sp.style.order = "9999"
      this.containerTarget.appendChild(sp)
    }
    sp.style.width = `${Math.round(width)}px`
  }

  // #1091 v4: Spacer auf das noetige Mass bringen — das Maximum aus
  //   (a) STEHENDEM Overscroll bis zur Voll-Regal-Position (alle Cards
  //       links eingestapelt, nur die rechte Card offen) — so schafft
  //       schon reines Links-Scrollen rechts Freiraum, und
  //   (b) dem Erhalt der AKTUELLEN Scrollposition (nach Closes darf
  //       nichts nachklemmen).
  // Laeuft zentral aus restickify() (= nach jeder Layout-Aenderung:
  // Connect, Append, Close-Removal, Morph, Collapse, Card-Resize) und
  // raeumt bei leerem Stack/Mobile auf.
  _syncEndSpacer() {
    const c  = this.containerTarget
    const sp = this._endSpacer()
    const cards = Array.from(c.querySelectorAll(".stack-card"))
    if (this._mediaMobile?.matches || !cards.length) {
      sp?.remove()
      return
    }
    const spacerW = sp ? (parseFloat(sp.style.width) || 0) : 0
    const natural = c.scrollWidth - spacerW
    let lastCardX = 0
    for (let i = 0; i < cards.length - 1; i++) lastCardX += cards[i].getBoundingClientRect().width
    const standing = standingSpacerWidth({
      clientWidth:    c.clientWidth,
      contentWidth:   natural,
      lastCardX,
      lastStickyLeft: parseFloat(cards[cards.length - 1].style.left) || 0
    })
    const preserve = endSpacerWidth({
      scrollLeft:   c.scrollLeft,
      clientWidth:  c.clientWidth,
      contentWidth: natural
    })
    this._setEndSpacerWidth(Math.max(standing, preserve))
  }

  // #1501 R3: Position nach einem Card-Ersatz wiederherstellen.
  //
  // Die Reihenfolge ist der ganze Punkt: ERST den Freiraum zurueckgeben, DANN
  // scrollen. Andersherum begrenzt `max` gegen einen Container, der gerade
  // schmaler ist als der, in dem der Nutzer stand — und die Position ist weg,
  // obwohl sie gleich wieder moeglich waere. `_syncEndSpacer` pendelt den
  // Spacer beim naechsten restickify() von selbst wieder ein, dann aber gegen
  // die WIEDERHERGESTELLTE Position. Gleiches Vorgehen wie nach dem Morph.
  _restoreScrollAfterUmbau(scrollVorher, spacerVorher) {
    if (spacerVorher > 0 && !this._mediaMobile?.matches) {
      this._setEndSpacerWidth(Math.max(spacerVorher, this._endSpacerWidthNow()))
    }
    const max = Math.max(0, this.containerTarget.scrollWidth - this.containerTarget.clientWidth)
    this.containerTarget.scrollLeft = Math.min(scrollVorher, max)
  }

  // #1091 v4: Regal-Schritt — eine Wheel-/Tastatur-Geste im Freiraum.
  // Vorwaerts (dir>0): naechste Card rueckt in den linken Spine-Stapel.
  // Rueckwaerts (dir<0): die zuletzt eingestapelte faehrt wieder aus.
  // Stops = Scrollpositionen, an denen Card i exakt an ihrem Sticky-
  // Platz sitzt (restickify hat style.left geschrieben).
  _shelfStep(dir, cards) {
    const c = this.containerTarget
    const stops = []
    let x = 0
    cards.forEach(card => {
      stops.push(Math.max(0, x - (parseFloat(card.style.left) || 0)))
      x += card.getBoundingClientRect().width
    })
    const target = dir > 0 ? nextShelfStop(stops, c.scrollLeft) : prevShelfStop(stops, c.scrollLeft)
    if (target == null) return
    c.scrollTo({ left: target, behavior: "smooth" })
  }

  // Steht der Viewport rechts vom natuerlichen Content-Ende (= im
  // Freiraum)? Dann uebersetzen sich Rueckwaerts-Gesten in Regal-
  // Schritte statt in Fokus-Wechsel.
  _inOverscroll() {
    const c = this.containerTarget
    const naturalMax = Math.max(0, (c.scrollWidth - this._endSpacerWidthNow()) - c.clientWidth)
    return c.scrollLeft > naturalMax + 1
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
      this._focusCardBody(next)   // #1486
      next.scrollIntoView({ behavior: "smooth", inline: "start", block: "nearest" })
      return
    }
    const idx = Math.max(0, cards.findIndex(c => c.dataset.active === "true"))
    // #1091 v4 (Hans): Am Stack-Ende ist ein Vorwaerts-Schritt kein No-Op
    // mehr — er scrollt weiter ins Regal: pro Geste rueckt eine weitere
    // Card in den linken Spine-Stapel, rechts waechst der Freiraum, bis
    // nur noch die aeusserste rechte Card offen ist. Rueckwaerts im
    // Freiraum: Regal-Schritt zurueck (Card faehrt wieder aus), erst
    // danach normale Fokus-Navigation.
    if (delta > 0 && idx === cards.length - 1) { this._shelfStep(+1, cards); return }
    if (delta < 0 && this._inOverscroll())     { this._shelfStep(-1, cards); return }
    const targetIdx = Math.min(cards.length - 1, Math.max(0, idx + delta))
    const next = cards[targetIdx]
    if (!next || next === cards[idx]) return
    this.setActiveCard(next)
    this._focusCardBody(next)   // #1486
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

  // Spine-Marker-Logic (Instance-Counter, Spine-Top-Close) ist in
  // `lib/blade_stack_spine.js`
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
      this._showBladeError(`Card konnte nicht geladen werden (${res.status})`)
      return
    }
    const html = await res.text()
    const { nodes, card } = this._parseCardHtml(html)   // #621
    if (!card) return
    this.containerTarget.querySelectorAll(":scope > p").forEach(el => el.remove())

    // #1501 R3: Position VOR dem Umbau merken. Beim Ersetzen kann die neue
    // Card schmaler sein als die weggenommene — dann faellt das Maximum
    // zurecht, und ohne Wiederherstellung bliebe der Stapel dort stehen, wohin
    // der Browser ihn gekappt hat. Dasselbe Muster wie im Zweig „links
    // einfuegen" und in _oeffneNeben (R2); nur dieser Pfad hatte es nie.
    const scrollVorher = this.containerTarget.scrollLeft
    // Und die Spacer-Breite dazu. Der End-Freiraum ist zum Teil aus der
    // Scrollposition selbst abgeleitet (#1091 v4: max(stehend, erhaltend)).
    // Kappt der Browser die Position waehrend des Umbaus, faellt beim
    // naechsten restickify() auch der erhaltende Anteil weg — und dann hat
    // die Wiederherstellung kein Ziel mehr, auf das sie zurueckkoennte.
    // Dasselbe Rezept wie beim Page-Morph (#1091 v3b, _morphSpacerW).
    const spacerVorher = this._endSpacerWidthNow()

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
    if (sourceListCard && mode === "replace_substack") {
      this._restoreScrollAfterUmbau(scrollVorher, spacerVorher)
    }
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
  // #1501 R3: NUR Cards einsammeln. Folgt kein weiteres Listen-Blade, liefert
  // _subStackEndElement null und die Schleife laeuft bis ans Container-Ende —
  // dort steht der stehende Spacer (#1091 v4) als direktes Kind. Ohne diesen
  // Filter wurde er mitentfernt, und er ist genau das, was rechts den Freiraum
  // haelt: `scrollWidth` faellt, die maximale Scrollposition sinkt unter die
  // aktuelle, und der BROWSER kappt `scrollLeft`. Ein gekappter Wert ist weg.
  // (Der Spacer taucht danach wieder auf — restickify legt ihn neu an. Genau
  // das macht den Fehler so schwer zu sehen: Am Ende sieht alles vollstaendig
  // aus, nur die Scrollposition fehlt.)
  _replaceSubStackAfter(sourceListCard) {
    const endEl = this._subStackEndElement(sourceListCard)
    const doomed = []
    let cur = sourceListCard.nextElementSibling
    while (cur && cur !== endEl) {
      if (cur.classList?.contains("stack-card")) doomed.push(cur)
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
    // #1283 (Hans): Ein Refresh ist KEINE Stack-Mutation. Das replaceWith
    // unten ist aber eine childList-Aenderung wie jeder Append, und der
    // MutationObserver hat sie bisher auch so behandelt — inklusive
    // Scroll auf die Voll-Regal-Position. Wer eine Card aktualisierte,
    // waehrend rechts Platz war, sah den Stack wegspringen. Das Flag
    // sagt dem Observer: Layout nachziehen ja, Fokus/Scroll/Trail nein.
    const wasActive = old.dataset.active === "true"
    // #1674 (aus immoOS #1473 uebernommen, Hans dort): „Das Refresh sollte nur
    // die Inhalte aktualisieren, nicht die Card-Breite zuruecksetzen." Fuehrt
    // eine Card ihre Breite selbst (`data-own-width`), nimmt die frische Card
    // Markierung UND Breite mit: Sonst steht sie zwischen Einhaengen und
    // Stimulus-Connect kurz in der CSS-Standardbreite, und wer in dieser Luecke
    // misst (Sticky-Offsets, Ueberstand) rechnet mit einer Breite, die es nie gab.
    const eigeneBreite = old.dataset.ownWidth
    const breiteVorher = old.style.width
    this._refreshingCard = true
    old.replaceWith(...nodes)
    if (wasActive) fresh.dataset.active = "true"
    if (eigeneBreite) {
      fresh.dataset.ownWidth = eigeneBreite
      if (breiteVorher) {
        fresh.style.width    = breiteVorher
        fresh.style.maxWidth = "none"
      }
    }
    // Erst im naechsten Macrotask zuruecksetzen — der Observer-Callback
    // laeuft als Microtask noch vor dem Timeout und sieht das Flag.
    setTimeout(() => { this._refreshingCard = false }, 0)
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

  // #1674 (aus immoOS #1348 uebernommen): Zur bereits offenen Card springen —
  // aufklappen, hinscrollen, aktiv setzen. „Springen sticht alles" (Hans dort):
  // Es entsteht keine zweite Kopie; wer die will, hat das Duplizieren-Icon.
  _springeZu(stackId, anchor = null) {
    const card = this.cardForUuid(stackId)
    if (!card) return
    this._expandCard(card)
    this._scrollCardIntoFocus(card)
    this.setActiveCard?.(card)
    if (anchor) this.scrollToAnchorInCard(card, anchor)
  }

  // #1674 (aus immoOS #1483 uebernommen): Klick-Action
  // `blade-stack#oeffneStattdessen` — diese Card wird durch eine ANDERE
  // ersetzt, an derselben Stelle, in derselben Breite. Gedacht fuer „vor/
  // zurueck" innerhalb einer Card (dort: zum naechsten Umsatz blaettern). Ein
  // normaler Aufruf haengte stattdessen eine zweite Card an; nach zehnmal
  // Blaettern haette man zehn Cards. Das Ziel steht in `data-target-uuid`.
  async oeffneStattdessen(event) {
    if (event) event.preventDefault()
    const trigger = event.currentTarget
    const alt     = trigger.closest(".stack-card")
    const ziel    = trigger.dataset.targetUuid
    if (!alt || !ziel) return
    // Schon offen? Dann dorthin springen statt eine zweite Instanz zu bauen.
    const offen = this.cardForUuid(ziel)
    if (offen && offen !== alt) {
      this._springeZu(ziel)
      return
    }
    await this._tauscheCardInhalt(alt, ziel)
  }

  // #1677 (aus immoOS #1665 übernommen; Hans dort): „Wechselt man den Reiter, bleibt die Card aber
  // stehen; man muss erneut auf das Fragezeichen klicken." — Jetzt nicht mehr.
  //
  // Der Reiterwechsel meldet sich (simple_tabs#_activate), der Stapel sieht
  // nach, ob zu DIESER Karte gerade eine Hilfe offen ist, und tauscht ihren
  // Inhalt. Keine Stack-Mutation: derselbe Platz, andere Erklärung.
  //
  // Drei Dinge, die der Handler NICHT tut: auf verschachtelte Reiterleisten
  // hören (sie unterteilen denselben Bereich — so hält es auch das
  // Fragezeichen, lib/help_tab), eine Hilfe aufmachen, die gar nicht offen
  // ist, und eine fremde Hilfe anfassen (sie gehört einer anderen Karte).
  async _hilfeFolgtReiter(event) {
    const quelle = event.target?.closest?.("article.stack-card")
    if (!quelle) return
    // Nur die äußerste Reiterleiste der Karte zählt.
    if (quelle.querySelector('[data-controller~="simple-tabs"]') !== event.target) return

    // Die Karten-ART steht schon am Fragezeichen — der Server hat sie berechnet
    // (HilfeHelper#hilfe_schluessel); sie hier ein zweites Mal aus der uuid zu
    // erraten hieße, dieselbe Regel zweimal zu pflegen.
    const basis  = quelle.querySelector("button.spine-hilfe-icon")?.dataset?.helpLinkIdValue
    const offene = [...this.containerTarget.querySelectorAll('article.stack-card[data-uuid^="help:"]')]
    const ziel   = hilfeTauschZiel(basis, offenerReiter(quelle), offene.map((k) => k.dataset.uuid))
    if (!ziel) return

    const karte = offene.find((k) => hilfeBasis(k.dataset.uuid) === basis)
    if (karte) await this._tauscheCardInhalt(karte, ziel)
  }

  // Derselbe Platz im Stapel, anderer Inhalt (immoOS #1665: eigene Methode,
  // damit nicht zwei Fassungen davon auseinanderlaufen).
  //
  // Wie beim Refresh (#1283): keine Stack-Mutation, also kein Trail-Schritt und
  // kein Scroll-Sprung. Breite und Aktiv-Markierung bleiben beim Platz, nicht
  // beim Inhalt.
  async _tauscheCardInhalt(alt, ziel) {
    const url = this._urlForStackId(ziel)
    if (!url) return false
    const res = await fetch(url, { headers: { "Accept": "text/html" } })
    if (!res.ok) { this._showBladeError(`Card konnte nicht geladen werden (${res.status})`); return false }
    const { nodes, card } = this._parseCardHtml(await res.text())
    if (!card) return false
    const warAktiv = alt.dataset.active === "true"
    const breite   = alt.style.width
    this._refreshingCard = true
    alt.replaceWith(...nodes)
    if (warAktiv) card.dataset.active = "true"
    if (breite) { card.style.width = breite; card.style.maxWidth = "none" }
    setTimeout(() => { this._refreshingCard = false }, 0)
    this._applySavedWidth(card)
    this.restickify()
    this.applyHighlighting()
    this.syncUrl({ pushHistory: false })
    return true
  }

  // #1198 v4: optional beforeNode — der Trail-Diff fügt fehlende Cards
  // an ihrer Position ein statt nur ans Ende (Back nach dem Schließen
  // einer mittleren Card).
  // #1509 (aus immoos #1348 uebernommen): die Weiche fuer die vier
  // Oeffnungsarten. Was der Klick meint, entscheidet der Modifier —
  // ersetzen (nichts gedrueckt), rechts (Umschalt), links (Umschalt+Alt),
  // ans Ende (Alt).
  async _oeffneNeben(stackId, url, quelle, art) {
    // Ans Ende haengen kann der gewachsene Weg schon — hier nur die Weiche.
    if (art === "ende") {
      await this._appendBladeAtUrl({ stackId, url })
      return true
    }
    // #1501 R2 (gemeldet von immoos_builder, mit Browser-Zahlen von Hans belegt):
    // Beim Ersetzen wurden die alten Cards ENTFERNT, bevor die neue geladen war
    // — und dazwischen liegt ein Netzwerk-Zugriff, also eine echte Pause. Das
    // Entfernen weckt den MutationObserver (er reagiert auch auf entfernte
    // Knoten), der laesst restickify() und damit _syncEndSpacer() laufen; der
    // End-Freiraum schrumpft auf die verbliebenen Cards, die maximale
    // Scrollposition faellt unter den aktuellen Wert, und der BROWSER kappt
    // scrollLeft. Ein gekappter Wert ist weg — das spaetere Einfuegen holt ihn
    // nicht zurueck. Sichtbar wurde das als aufklappende Spines links (Hans'
    // Messung im Fork: 388 → 0, Streifen 28 → 416 px).
    //
    // Deshalb: erst fragen, dann laden, und Entfernen + Einfuegen zum Schluss
    // in EINEM synchronen Zug. Nebengewinn: Schlaegt das Laden fehl, steht der
    // Stapel nicht mehr verstuemmelt da (alte Cards weg, neue nie gekommen).
    let doomed = []
    if (art === "ersetzen") {
      let cur = quelle.nextElementSibling
      while (cur) {
        if (cur.classList?.contains("stack-card")) doomed.push(cur)
        cur = cur.nextElementSibling
      }
      if (!this._confirmDiscardDrafts(doomed)) return false
    }

    const res = await fetch(url, { headers: { "Accept": "text/html" } })
    if (!res.ok) {
      console.warn("blade fetch failed", url, res.status)
      this._showBladeError(`Card konnte nicht geladen werden (${res.status})`)
      return false
    }
    const { nodes, card } = this._parseCardHtml(await res.text())
    if (!card) return false
    this.containerTarget.querySelectorAll(":scope > p").forEach(el => el.remove())

    if (art === "links") {
      // Links einfuegen schiebt alles nach rechts — ohne Ausgleich springt
      // das Bild unter den Augen des Nutzers weg. Deshalb die Scrollposition
      // um den Zuwachs mitziehen.
      const vorher       = this.containerTarget.scrollLeft
      const breiteVorher = this.containerTarget.scrollWidth
      nodes.forEach(n => this.containerTarget.insertBefore(n, quelle))
      this._uniquifyCardId(card)
      this._applySavedWidth(card)
      this.restickify()
      this.containerTarget.scrollLeft = vorher + (this.containerTarget.scrollWidth - breiteVorher)
    } else {
      // #1501 R2: Position VOR dem Umbau merken und danach begrenzt
      // wiederherstellen — dasselbe Muster wie im Zweig „links" darueber.
      // Entfernen und Einfuegen stehen bewusst ohne Unterbrechung beieinander.
      const vorher       = this.containerTarget.scrollLeft
      const spacerVorher = this._endSpacerWidthNow()
      doomed.forEach(c => c.remove())
      let ref = quelle
      nodes.forEach(n => { ref.after(n); ref = n })
      this._uniquifyCardId(card)
      this._applySavedWidth(card)
      this.restickify()
      this._restoreScrollAfterUmbau(vorher, spacerVorher)
    }
    requestAnimationFrame(() => this._scrollCardIntoFocus(card))
    return true
  }

  async appendCardBare(uuid, { beforeNode = null } = {}) {
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
    nodes.forEach(n => beforeNode ? this.containerTarget.insertBefore(n, beforeNode)
                                  : this.containerTarget.appendChild(n))
    this._applySavedWidth(card)   // #601
    requestAnimationFrame(() => {
      // Erste Card: links anlegen (scrollLeft=0). Folge-Cards: ganz
      // rechts ans Ende scrollen — #202: scrollIntoView trifft wegen
      // Sticky-Positioning oft daneben. #1091 v4: „Ende" = natuerliches
      // Content-Ende OHNE den stehenden Overscroll-Spacer.
      // #1198 v4: bei einer Mittel-Einfügung NICHT ans Ende scrollen —
      // die Nachbarn bleiben stehen, die neue Card kommt nearest ins Bild.
      if (wasEmpty) {
        this.containerTarget.scrollLeft = 0
      } else if (beforeNode) {
        card.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" })
      } else {
        // #1509: siehe openNewCard — dasselbe Zurueckspringen, andere Stelle.
        this._scrollCardIntoFocus(card)
      }
    })
  }

  // #1091 v4: Ziel-scrollLeft fuer „ans Content-Ende scrollen" — die
  // letzte Card rechtsbuendig, der stehende Overscroll-Spacer zaehlt
  // nicht als Content.
  _naturalEndScroll() {
    const c = this.containerTarget
    return Math.max(0, c.scrollWidth - this._endSpacerWidthNow() - c.clientWidth)
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

  // #1487: Neue Cards mit in die Breiten-Beobachtung nehmen. `observe`
  // auf eine schon beobachtete Card ist folgenlos, deshalb reicht es,
  // hier stumpf alle durchzugehen.
  _beobachteBreiten() {
    if (!this._breitenBeobachter) return
    this.containerTarget.querySelectorAll(".stack-card")
        .forEach(card => this._breitenBeobachter.observe(card))
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
    this._beobachteBreiten()   // #1487: frisch dazugekommene Cards mitnehmen
    // #224 (2026-05-19): cardWidth pro Card, nicht einmal aus cards[0].
    // #277 follow-up: optional widthsHint vom Caller, damit toggleCollapse
    // die Breiten VOR dem dataset-flip einliest. Sonst kommt der forced
    // reflow nach dem CSS-State-Change, und das committet den Endwert ins
    // Layout — die Breiten-Transition fuer die kollabierende Card wird
    // dabei verschluckt.
    // #1167: Offset-Mathematik (inkl. Letzte-Card-Klemmung aus #281 und
    // dem bei vielen Cards schrumpfenden Schritt) liegt als pure Funktion
    // in lib/blade_stack_sticky.js. Der effektive Schritt wird fuer die
    // Scroll-Mathematik (blade_stack_scroll.js) gemerkt.
    const widths = cards.map((card, i) =>
      (widthsHint && widthsHint[i] != null)
        ? widthsHint[i]
        : card.getBoundingClientRect().width
    )
    const { step, offsets } = stickyOffsets({
      widths,
      clientWidth: this.containerTarget.clientWidth,
      step: this.constructor.SPINE_STEP
    })
    this._stepEff = step
    cards.forEach((card, i) => {
      card.style.position = "sticky"
      card.style.left     = `${offsets[i].left}px`
      card.style.right    = `${offsets[i].right}px`
      card.style.zIndex   = String(offsets[i].zIndex)
    })
    // #1091 v4: Der End-Spacer haengt vom Layout ab (Voll-Regal-Position
    // braucht die frischen sticky-left-Werte) — hier zentral nachziehen.
    this._syncEndSpacer()
    // #1228: Breiten koennen sich geaendert haben (Resize, neue Card) —
    // der Ueberstand haengt an ihnen.
    this._clipOverhang()
  }

  // #1228 (Hans): Schneidet ab, was eine Card rechts ueber ihre
  // Nachfolgerin hinausragen laesst — im Regal-Zustand „schauten" breite
  // Cards sonst rechts an der vordersten vorbei. Rechenregel in
  // lib/blade_stack_overhang.js; hier nur Messen und Setzen.
  //
  // Erst ALLE Rects lesen, dann alle Styles schreiben: gemischtes
  // Lesen/Schreiben triebe pro Card einen Reflow, und das laeuft an
  // jedem Scroll-Frame.
  _clipOverhang() {
    if (this._mediaMobile?.matches) return   // Mobile: scroll-snap, kein Stapel
    const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
    if (cards.length === 0) return
    const rects = cards.map(c => c.getBoundingClientRect())
    overhangClips(rects).forEach((clip, i) => {
      const card = cards[i]
      const wanted = clip > 0 ? `inset(0 ${Math.round(clip)}px 0 0)` : ""
      // Nur schreiben, wenn sich etwas aendert — sonst invalidiert jeder
      // Scroll-Frame das Painting aller Cards.
      if (card.style.clipPath !== wanted) card.style.clipPath = wanted
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
