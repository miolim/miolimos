// #529 (Hans, 2026-06-06): Scroll-/Geometrie-Logik aus
// blade_stack_controller.js ausgelagert (Refactoring-Schritt 1). Reine
// sticky-aware Scroll-Mathematik auf Basis des Stack-Models
// (this.containerTarget, this.constructor.SPINE_STEP). Wird als Mixin auf
// das Controller-Prototype angewendet, damit `this` weiterhin den
// Stack-Controller meint. Reines Code-Move, KEIN Verhalten geändert —
// identisch zum bisherigen Inline-Code.
//
// Enthaltene Methoden:
//   scrollCardIntoView      — Card sticky-aware ins Viewport (next/prev/nearest)
//   _scrollLastIntoView     — letzte Card beim Reload/Append rechts positionieren
//   _scrollCardIntoFocus    — Append-Fall: letzte Card vs. Card in der Mitte
//   scrollToAnchorInCard    — zu einem #anker in einer Card scrollen (+ disclosure)
//   _handleWheel            — Wheel/Shift-Wheel → horizontaler Card-Fokus-Schritt
//   _syncActiveCardToScroll — Mobile: nach scrollend die nächste Card aktiv setzen

export const BladeStackScrollMixin = {
  scrollCardIntoView(card, idx, total, direction) {
    const allCards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
    if (idx == null || total == null) {
      idx   = allCards.indexOf(card)
      total = allCards.length
      if (idx < 0) return
    }
    const step  = this.constructor.SPINE_STEP
    const cw    = this.containerTarget.clientWidth
    // #224 (2026-05-19): Sticky-Positionierung macht `offsetLeft` und
    // `getBoundingClientRect()` unverlaesslich fuer "natuerliche
    // Scroll-Origin"-Berechnungen — die Card sitzt visuell ja gerade
    // sticky verschoben. Wir berechnen den natuerlichen Card-Anfang
    // im Content-Koordinatensystem durch kumulative Card-Breiten.
    let cardX = 0
    for (let i = 0; i < idx; i++) cardX += allCards[i].getBoundingClientRect().width
    const cardW      = card.getBoundingClientRect().width
    const minScroll  = Math.max(0, cardX + cardW - cw + (total - idx - 1) * step)
    const maxScroll  = Math.max(0, cardX - idx * step)
    const current   = this.containerTarget.scrollLeft
    let target = current
    if (direction === "next") {
      // Rechts-Anchor: nur scrollen, wenn die Card NICHT vollstaendig
      // sichtbar ist; dann auf minScroll (= Card rechtsbuendig).
      if (current < minScroll || current > maxScroll) target = minScroll
    } else if (direction === "prev") {
      // Links-Anchor.
      if (current < minScroll || current > maxScroll) target = maxScroll
    } else {
      // Nearest (Spine-Click / Item-Klick): klassisches Verhalten.
      if (current > maxScroll) target = maxScroll
      else if (current < minScroll) target = minScroll
    }
    if (target !== current) {
      this.containerTarget.scrollTo({ left: target, behavior: "smooth" })
    }
  },

  // #284 v3: sticky-aware Initial-Scroll fuer Reload. v2 nutzte
  // minScroll (cardX + cardW - cw) → Card-Right exakt am Container-
  // Rand, kein visueller Atemraum. v3 nutzt maxScroll (cardX -
  // idx*step), wenn der Bereich gueltig ist (= Card passt zwischen
  // Sticky-Block links und Container-Rechts): die Card sitzt dann
  // direkt rechts der Sticky-Spines mit reichlich Platz rechts.
  // Fallback minScroll, falls die Card zu breit ist (kann ohne
  // Sticky-Ueberlapp nicht voll dargestellt werden).
  _scrollLastIntoView(card) {
    const allCards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
    const idx   = allCards.indexOf(card)
    const total = allCards.length
    if (idx < 0) return
    const step  = this.constructor.SPINE_STEP
    const cw    = this.containerTarget.clientWidth
    let cardX = 0
    for (let i = 0; i < idx; i++) cardX += allCards[i].getBoundingClientRect().width
    const cardW     = card.getBoundingClientRect().width
    const minScroll = Math.max(0, cardX + cardW - cw + (total - idx - 1) * step)
    const maxScroll = Math.max(0, cardX - idx * step)
    // Bereich [min..max] gueltig wenn maxScroll >= minScroll. Dann
    // bevorzugt maxScroll (Card direkt rechts vom Sticky-Block,
    // Atemraum rechts). Sonst minScroll (= so weit rechts wie
    // moeglich, Sticky-Block ueberlappt Card-Left).
    //
    // #281 follow-up v2 (Hans, 2026-05-24): wenn der natuerliche
    // Sticky-Stapel die letzte Card nicht ins Viewport laesst (= die
    // i*step-Reihe wird breiter als cw - cardWidth), bringt maxScroll
    // sie nur an die geclampten Sticky-Position, NICHT ans Viewport-
    // Ende. Stattdessen scrollen wir zum „rechten Maximum"
    // (scrollLeftMax), damit die Card am rechten Rand des Containers
    // sitzt und vollstaendig sichtbar ist. Erkannt am Verhaeltnis von
    // Sticky-Stapel-Breite zu Viewport.
    const stickyStackWidth = idx * step
    const stickyClamped    = idx === total - 1 && stickyStackWidth > Math.max(0, cw - cardW)
    let target
    if (stickyClamped) {
      // scrollLeftMax fuer den Container: alles soweit nach rechts wie
      // moeglich. Card sitzt dann genau in cw-cardW (= rechter Rand).
      target = Math.max(0, this.containerTarget.scrollWidth - cw)
    } else {
      target = maxScroll >= minScroll ? maxScroll : minScroll
    }
    if (this.containerTarget.scrollLeft !== target) {
      this.containerTarget.scrollLeft = target
    }
  },

  _scrollCardIntoFocus(card) {
    if (this.containerTarget.dataset.mobile === "true") {
      const left = card.offsetLeft - this.containerTarget.offsetLeft
      this.containerTarget.scrollTo({ left, behavior: "smooth" })
    } else {
      // #292: wenn's die letzte Card ist (typischer Append-Fall),
      // gleiche sticky-aware Scroll-Math wie der Reload-Pfad —
      // _scrollLastIntoView bevorzugt maxScroll, damit die Card
      // rechts vom Sticky-Block sitzt mit Atemraum rechts. Bei
      // Cards in der Mitte bleibt das alte "next"-Verhalten
      // (minScroll, rechtsbuendig).
      const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
      if (cards[cards.length - 1] === card) {
        this._scrollLastIntoView(card)
      } else {
        // #270 follow-up: scrollIntoView({inline:"end"}) beruecksichtigt
        // die sticky-Spines der Vorgaenger-Cards nicht — der neue Blade
        // landet rechtsbuendig, aber kann teilweise von den sticky-rights
        // der vorigen Cards verdeckt sein. scrollCardIntoView mit
        // direction "next" rechnet das ueber kumulative Card-Breiten +
        // SPINE_STEP raus.
        this.scrollCardIntoView(card, undefined, undefined, "next")
      }
    }
  },

  scrollToAnchorInCard(card, anchor) {
    // Kleinen Tick warten, bis horizontal-scroll & Layout stabil sind —
    // sonst ist `el.offsetTop` relativ zu einem noch-nicht-positionierten
    // Container falsch.
    requestAnimationFrame(() => {
      const el = card.querySelector(`[id="${CSS.escape(anchor)}"]`)
      if (!el) return
      // #218: wenn der Anchor selbst oder ein Vorfahr eine
      // `data-controller=disclosure`-Komponente ist und der Content
      // collapsed (versteckt), programmatisch ausklappen. Sonst landet
      // der Scroll auf einem zusammengeklappten Header, der Body
      // bleibt unsichtbar (Kommentar-Disclosure aus #143).
      let cursor = el
      while (cursor && cursor !== card) {
        const controllers = cursor.dataset?.controller || ""
        if (controllers.split(/\s+/).includes("disclosure")) {
          const ctrl = this.application?.getControllerForElementAndIdentifier(cursor, "disclosure")
          ctrl?.expand?.()
        }
        cursor = cursor.parentElement
      }
      el.scrollIntoView({ behavior: "smooth", block: "center" })
      el.classList.add("anchor-flash")
      setTimeout(() => el.classList.remove("anchor-flash"), 1600)
    })
  },

  _handleWheel(event) {
    // #224 6f-4 v2: Auf Mobile uebernimmt der Browser den nativen
    // Snap-Scroll — kein Wheel-Hijack.
    if (this._mediaMobile?.matches) return
    // Vertikaler Standard-Scroll innerhalb einer Card (z.B. langer Body)
    // soll NICHT abgefangen werden — der User scrollt im Card-Inhalt
    // weiter. Daher: nur wenn deltaX dominant ist (oder Shift+Wheel —
    // klassisches Browser-Idiom fuer Horizontal-Scroll).
    const dx = event.shiftKey ? event.deltaY : event.deltaX
    if (Math.abs(dx) < 1) return
    if (Math.abs(dx) < Math.abs(event.deltaY) && !event.shiftKey) return

    event.preventDefault()
    const now = performance.now()
    if (now < this._wheelLockedUntil) return

    // #269/#271: Schwellwert + Lock kommen aus den User-Vorlieben
    // (Settings/Vorlieben → Wheel-Preset). Defaults entsprechen dem
    // bisherigen Verhalten.
    const THRESH = this.wheelThresholdValue || 20
    this._wheelAccumX += dx
    if (Math.abs(this._wheelAccumX) < THRESH) return

    const delta = this._wheelAccumX > 0 ? +1 : -1
    this._wheelAccumX = 0
    this._wheelLockedUntil = now + (this.wheelLockMsValue || 110)
    this.moveActive(delta)
  },

  _syncActiveCardToScroll() {
    if (!this._mediaMobile?.matches) return
    const container = this.containerTarget
    const containerRect = container.getBoundingClientRect()
    // Card, deren linke Kante am dichtesten am Container-Left liegt
    // (mit Toleranz fuer Spine-Breite, ~28px).
    let best = null
    let bestDist = Infinity
    container.querySelectorAll(".stack-card").forEach(card => {
      const rect = card.getBoundingClientRect()
      const dist = Math.abs(rect.left - containerRect.left)
      if (dist < bestDist) {
        best = card
        bestDist = dist
      }
    })
    if (best) this.setActiveCard(best)
  }
}
