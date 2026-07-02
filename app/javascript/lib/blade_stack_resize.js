// #803 (aus #801 R5): Card-Resize (#163 Phase 6e: Breite pro Card-Kind, localStorage-persistiert, Drag-Handle + Doppelklick-Reset).
// Aus blade_stack_controller.js extrahiert — wird als Mixin aufs
// Prototype gemixt (Muster #378/#529), damit `this` weiterhin den
// Stack-Controller meint (Targets, Values, Helpers). Reines Code-Move.
//
// Enthaltene Methoden: _isDesktop · _cardKind · _applySavedWidth · _setWidthInstant · _setupResizeForCard · _startResize · _resizeMove · _resizeUp · _resetResize

export const BladeStackResizeMixin = {
// ─── #163 Phase 6e: Card-Resize ─────────────────────────────────────
//
// Pro Card-Kind eine Breite, persistiert in localStorage. Drag am
// 6px-Handle am rechten Card-Rand setzt die Breite per inline-style;
// Doppelklick = Reset auf Default. Mobile (< md) bekommt das Handle
// nicht — Hans's Spec: „6e nur fuer groessere Bildschirmaufloesungen".

_isDesktop() { return window.innerWidth >= 768 },
// #601: gemerkte Breite (localStorage blade.width.<kind> bzw. User-Pref)
// SOFORT auf eine frisch eingefügte Card anwenden — vorher kam sie erst
// verspätet (Layout-Pass), und _scrollCardIntoFocus rechnete mit der
// CSS-Default-Breite: die verbreiterte Card ragte rechts aus dem Fenster.
_applySavedWidth(card) {
  if (this._mediaMobile?.matches) return
  const kind  = this._cardKind(card)
  const saved = parseInt(localStorage.getItem(`blade.width.${kind}`), 10)
  const remPx = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16
  if (Number.isFinite(saved) && saved >= 280) {
    this._setWidthInstant(card, saved)
  } else if (this.cardWidthsValue && this.cardWidthsValue[kind]) {
    const px = Math.round(this.cardWidthsValue[kind] * remPx)
    if (px >= 280) this._setWidthInstant(card, px)
  }
},

// #601 v2 (Hans-Repro Topicprops): .stack-card hat eine width-Transition
// (220ms, für Smooth-Close/Resize). Die ließ die frisch gesetzte Breite
// ANIMIEREN — die Scroll-Berechnung im nächsten Frame maß noch die
// Default-Breite und positionierte die Card zu weit links (Teil ragte
// rechts raus). Für die Initial-Breite einer frisch eingefügten Card
// die Transition einmalig aussetzen: Breite steht sofort, der Scroll
// rechnet richtig. Gilt für ALLE Blade-Typen (zentraler Pfad).
_setWidthInstant(card, px) {
  card.style.transition = "none"
  card.style.width      = `${px}px`
  card.style.maxWidth   = "none"
  card.getBoundingClientRect()   // Reflow erzwingen — Breite gilt JETZT
  requestAnimationFrame(() => { card.style.transition = "" })
},

_cardKind(card) {
  const uuid = card.dataset.uuid || ""
  // Per-Listen-Blade-Typ separat speichern (list:tasks anders breit als
  // list:topic), Detail-Cards pro Type-Praefix gemeinsam (task/topic/...).
  // #357 / #343: zusammengesetzte Praefixe expliziert mappen, damit sie
  // in den Preferences als eigene Kinds erscheinen.
  if (uuid.startsWith("render:topic:")) return "topic_render"
  if (uuid.startsWith("refs:ki:"))      return "ki_refs"
  if (uuid.startsWith("refs:topic:"))   return "topic_refs"
  // #484 (Hans, 2026-06-03): Topic-Blade pro Reiter/Topic NICHT eigene
  // Breite. Das uuid traegt Slug + Tab (`list:topic:<slug>[:<tab>]`),
  // wodurch jede Reiter/Topic-Kombi einen eigenen Breiten-Key bekam und
  // die Breite beim Tab-Wechsel/aus der Mutter-Liste „erbte". Auf einen
  // stabilen Kind kollabieren -> einheitliche Topic-Blade-Breite.
  if (uuid.startsWith("list:topic:"))   return "list:topic"
  if (uuid.startsWith("list:"))         return uuid
  if (uuid.includes(":"))               return uuid.split(":")[0]
  return "ki"  // Knowledge-Items kommen als pure UUID daher.
},

_setupResizeForCard(card) {
  if (!this._isDesktop()) return
  if (card.querySelector(":scope > .blade-resize-handle")) return

  // Gespeicherte Breite restoren — Reihenfolge:
  //   1. localStorage (= zuletzt per Resize-Handle eingestellt)
  //   2. User-Pref aus cardWidthsValue (Settings/Vorlieben) in rem → px
  //   3. CSS-Default (im Partial via Tailwind w-[…rem])
  const kind  = this._cardKind(card)
  const saved = parseInt(localStorage.getItem(`blade.width.${kind}`), 10)
  if (Number.isFinite(saved) && saved >= 280) {
    card.style.width    = `${saved}px`
    card.style.maxWidth = "none"
  } else if (this.cardWidthsValue && this.cardWidthsValue[kind]) {
    // rem → px via getComputedStyle (1rem = root font-size)
    const remPx = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16
    const px    = Math.round(this.cardWidthsValue[kind] * remPx)
    if (px >= 280) {
      card.style.width    = `${px}px`
      card.style.maxWidth = "none"
    }
  }

  // Handle injecten.
  const handle = document.createElement("div")
  handle.className = "blade-resize-handle"
  handle.title     = "Breite ziehen — Doppelklick = Default"
  handle.addEventListener("pointerdown", (e) => this._startResize(e, card))
  handle.addEventListener("dblclick",    () => this._resetResize(card))
  card.appendChild(handle)
},

_startResize(event, card) {
  event.preventDefault()
  event.stopPropagation()
  const rect = card.getBoundingClientRect()
  this._resizeState = {
    card,
    startX: event.clientX,
    startWidth: rect.width,
    kind: this._cardKind(card)
  }
  document.body.style.cursor    = "col-resize"
  document.body.style.userSelect = "none"
  this._onResizeMove = (e) => this._resizeMove(e)
  this._onResizeUp   = (e) => this._resizeUp(e)
  window.addEventListener("pointermove", this._onResizeMove)
  window.addEventListener("pointerup",   this._onResizeUp)
},

_resizeMove(event) {
  const s = this._resizeState
  if (!s) return
  const delta    = event.clientX - s.startX
  const maxWidth = window.innerWidth - 80
  const newWidth = Math.max(280, Math.min(maxWidth, s.startWidth + delta))
  s.card.style.width    = `${newWidth}px`
  s.card.style.maxWidth = "none"
},

_resizeUp(_event) {
  const s = this._resizeState
  if (!s) return
  const finalWidth = Math.round(s.card.getBoundingClientRect().width)
  localStorage.setItem(`blade.width.${s.kind}`, String(finalWidth))
  this._resizeState           = null
  document.body.style.cursor   = ""
  document.body.style.userSelect = ""
  window.removeEventListener("pointermove", this._onResizeMove)
  window.removeEventListener("pointerup",   this._onResizeUp)
  this.restickify()
},

_resetResize(card) {
  const kind = this._cardKind(card)
  localStorage.removeItem(`blade.width.${kind}`)
  card.style.width    = ""
  card.style.maxWidth = ""
  this.restickify()
}
}
