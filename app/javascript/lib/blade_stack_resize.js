// #803 (aus #801 R5): Card-Resize (#163 Phase 6e: Breite pro Card-Kind, localStorage-persistiert, Drag-Handle + Doppelklick-Reset).
// Aus blade_stack_controller.js extrahiert — wird als Mixin aufs
// Prototype gemixt (Muster #378/#529), damit `this` weiterhin den
// Stack-Controller meint (Targets, Values, Helpers). Reines Code-Move.
//
// Enthaltene Methoden: _isDesktop · _cardKind · _applySavedWidth · _setWidthInstant · _setupResizeForCard · _startResize · _resizeMove · _resizeUp · _resetResize · _adoptWidthAsDefault

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
  handle.title     = window.t("js.blade_stack.resize_handle_title")
  handle.addEventListener("pointerdown", (e) => this._startResize(e, card))
  // #1152: STRG-Doppelklick (Mac: Cmd) uebernimmt die aktuelle Breite als
  // neue Standard-Breite; normaler Doppelklick setzt auf den Standard zurueck.
  handle.addEventListener("dblclick", (e) => {
    if (e.ctrlKey || e.metaKey) this._adoptWidthAsDefault(card)
    else this._resetResize(card)
  })
  card.appendChild(handle)
},

_startResize(event, card) {
  event.preventDefault()
  event.stopPropagation()
  const rect = card.getBoundingClientRect()
  this._resizeState = {
    card,
    lastX: event.clientX,
    width: rect.width,
    kind: this._cardKind(card)
  }
  document.body.style.cursor    = "col-resize"
  document.body.style.userSelect = "none"
  this._onResizeMove = (e) => this._resizeMove(e)
  this._onResizeUp   = (e) => this._resizeUp(e)
  window.addEventListener("pointermove", this._onResizeMove)
  window.addEventListener("pointerup",   this._onResizeUp)
},

// #1154: Mit gedrueckter STRG-Taste (Mac: Cmd) invertiert die Mausbewegung —
// nach links ziehen macht die Card BREITER. Noetig fuer die aeusserst rechte
// Card, wo rechts vom Handle kein Platz mehr ist. Inkrementell akkumuliert
// (statt Abstand zum Startpunkt), damit STRG mitten im Zug gedrueckt/
// losgelassen werden kann, ohne dass die Breite springt.
_resizeMove(event) {
  const s = this._resizeState
  if (!s) return
  const dx = event.clientX - s.lastX
  s.lastX  = event.clientX
  s.width += (event.ctrlKey || event.metaKey) ? -dx : dx
  const maxWidth = window.innerWidth - 80
  const newWidth = Math.max(280, Math.min(maxWidth, s.width))
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
  // #1152: „Standardeinstellung" ist die User-Pref (Settings → Vorlieben,
  // bzw. per STRG-Doppelklick uebernommen), erst danach der CSS-Default.
  if (this.cardWidthsValue && this.cardWidthsValue[kind]) {
    const remPx = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16
    const px    = Math.round(this.cardWidthsValue[kind] * remPx)
    if (px >= 280) this._setWidthInstant(card, px)
  }
  this.restickify()
},

// #1152: STRG-Doppelklick auf das Handle — die aktuelle Breite dieser Card
// wird die neue Standard-Breite ihres Kinds: serverseitig in der User-Pref
// card_widths gespeichert (in rem, wie in Settings → Vorlieben editierbar).
// Der localStorage-Override wird geloescht — Standard und aktuelle Breite
// sind jetzt identisch, und der Doppelklick-Reset landet kuenftig hier.
async _adoptWidthAsDefault(card) {
  const kind  = this._cardKind(card)
  const remPx = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16
  const rem   = Math.round(card.getBoundingClientRect().width / remPx)
  const body  = new URLSearchParams()
  body.append(`preferences[card_widths][${kind}]`, String(rem))
  let ok = false
  try {
    const resp = await fetch("/settings/preferences", {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
        "Accept":       "application/json"
      },
      body
    })
    ok = resp.ok
  } catch { /* Netzfehler → Toast unten */ }
  if (!ok) {
    this._flashToast(window.t("js.blade_stack.width_default_failed"))
    return
  }
  this.cardWidthsValue = { ...this.cardWidthsValue, [kind]: rem }
  localStorage.removeItem(`blade.width.${kind}`)
  this._setWidthInstant(card, Math.round(rem * remPx))
  this._flashToast(window.t("js.blade_stack.width_default_saved"))
}
}
