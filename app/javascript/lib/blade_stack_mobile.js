// #803 (aus #801 R5): Mobile-Layout (#224 6f-4 v2: native scroll-snap; Breiten-Reset + Wiederherstellung beim Breakpoint-Wechsel).
// Aus blade_stack_controller.js extrahiert — wird als Mixin aufs
// Prototype gemixt (Muster #378/#529), damit `this` weiterhin den
// Stack-Controller meint (Targets, Values, Helpers). Reines Code-Move.
//
// Enthaltene Methoden: _applyMobileLayout

export const BladeStackMobileMixin = {
// ─── Mobile-Layout (#224 6f-4 v2: native scroll-snap) ──────────

_applyMobileLayout() {
  const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card"))
  if (cards.length === 0) return
  const isMobile = this._mediaMobile?.matches
  this.containerTarget.dataset.mobile = isMobile ? "true" : "false"
  if (!isMobile) {
    // Saved-Width pro Card aus localStorage wiederherstellen.
    // #408 follow-up (Hans, 2026-05-30): Reihenfolge muss zur
    // `_setupResizeForCard`-Logik passen — sonst kommt
    // `cardWidthsValue` (User-Pref aus Settings, z.B. 38rem fuer
    // Tasks = 608px) ueber `_setupResizeForCard` IN den DOM, wird
    // hier auf "" zurueckgesetzt, und der nachfolgende stickyRight
    // wird mit dem CSS-Default (36rem = 576) berechnet — obwohl die
    // Card spaeter wieder auf 608 expandiert. Folge: Sticky-Rechts-
    // Stack rutscht ~32px nach LINKS in den Viewport, Content
    // sichtbar neben dem Spine.
    const remPx = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16
    cards.forEach(card => {
      const kind  = this._cardKind(card)
      const saved = parseInt(localStorage.getItem(`blade.width.${kind}`), 10)
      if (Number.isFinite(saved) && saved >= 280) {
        card.style.width    = `${saved}px`
        card.style.maxWidth = "none"
      } else if (this.cardWidthsValue && this.cardWidthsValue[kind]) {
        const px = Math.round(this.cardWidthsValue[kind] * remPx)
        if (px >= 280) {
          card.style.width    = `${px}px`
          card.style.maxWidth = "none"
        } else {
          card.style.width    = ""
          card.style.maxWidth = ""
        }
      } else {
        card.style.width    = ""
        card.style.maxWidth = ""
      }
    })
    // Sticky-Layout zurueck (restickify wuerde re-entrant rufen).
    // #408 (Hans, 2026-05-30): cardWidth muss PRO Card berechnet
    // werden — die alte Single-cardWidth-Variable nutzte
    // cards[0].width und behauptete damit fuer alle Cards die
    // Breite der List-Card (704px). Folge: stickyRight zu negativ
    // → Cards rechts vom Fokus stapeln ihre Spines ausserhalb des
    // Viewports, anstatt am rechten Rand sichtbar zu bleiben.
    const step  = this.constructor.SPINE_STEP
    const total = cards.length
    cards.forEach((card, i) => {
      const cardWidth = card.getBoundingClientRect().width
      card.style.position  = "sticky"
      card.style.left      = `${i * step}px`
      card.style.right     = `${(total - i) * step - cardWidth}px`
      card.style.zIndex    = String(i)
    })
    return
  }
  // Mobile-Mode: alle JS-inline-Reste aus dem alten Pfad killen.
  // Das CSS (`@media (max-width: 767px)`) uebernimmt den Rest:
  // overflow-x: auto + scroll-snap-type: x mandatory + flex 0 0 100vw.
  cards.forEach(card => {
    card.style.position  = ""
    card.style.top       = ""
    card.style.left      = ""
    card.style.right     = ""
    card.style.width     = ""
    card.style.maxWidth  = ""
    card.style.transform = ""
    card.style.transition = ""
    card.style.zIndex    = ""
    card.style.visibility = ""
    delete card.dataset.collapsed
  })
  // Aktive Card ins Viewport scrollen.
  const active = cards.find(c => c.dataset.active === "true") || cards[cards.length - 1]
  if (active) {
    requestAnimationFrame(() => {
      active.scrollIntoView({ behavior: "auto", inline: "start", block: "nearest" })
    })
  }
}
}
