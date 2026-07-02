// #403 (Hans, 2026-05-30): Beim Re-Rendern eines Turbo-Frames oder
// Turbo-Streams resettet der Browser den scrollTop der umgebenden
// Scroll-Container, weil sich der Inhalt ersetzt. Hans's Wunsch:
// Scroll-Position bei allen Klicks (Edit↔Read, Save, KI-Filter etc.)
// erhalten.
//
// Strategie (Iter 3 — Edit-Pencil auf standalone KI scrollte zurueck,
// weil der relevante Scroller das App-Shell-`<main>`-Element ist und
// nicht in der Stack-Card-Hierarchie liegt):
//   1. Snapshot vor jeder Turbo-Aktion: scrollTops aller scrollbaren
//      Elemente im DOM (overflow-y auto/scroll mit scrollTop > 0).
//      Wir referenzieren die Elements direkt — Turbo ersetzt nur die
//      Frame-Children, die Scroll-Container selbst bleiben in der DOM.
//   2. Nach `turbo:frame-render` / `turbo:render` / `turbo:after-stream-render`
//      via `requestAnimationFrame` wiederherstellen, sofern das Element
//      noch im Dokument haengt.
//
// Echte Visits (`turbo:before-visit`) suppressen wir den Restore —
// dort erwartet der User einen frischen Page-Top.

let saved = []  // Array<{ el, top }>
let suppressNextRestore = false

function snapshot() {
  saved.length = 0
  // Stack-Card-Scroller, Body-Scrollcontainer, und das App-Shell-<main>
  // teilen sich alle die Klasse `overflow-y-auto`. Ein generischer
  // Scan deckt alle ab.
  document.querySelectorAll(".overflow-y-auto, .overflow-auto").forEach((el) => {
    if (el.scrollTop > 0) saved.push({ el, top: el.scrollTop })
  })
  if (window.scrollY > 0) saved.push({ el: window, top: window.scrollY })
}

function restore() {
  if (suppressNextRestore) {
    saved.length = 0
    suppressNextRestore = false
    return
  }
  if (saved.length === 0) return
  requestAnimationFrame(() => {
    saved.forEach(({ el, top }) => {
      if (el === window) {
        window.scrollTo(0, top)
      } else if (el.isConnected) {
        el.scrollTop = top
      }
    })
    saved.length = 0
  })
}

document.addEventListener("turbo:before-stream-render", snapshot)
document.addEventListener("turbo:before-fetch-request", snapshot)
document.addEventListener("turbo:before-visit", () => { suppressNextRestore = true })
document.addEventListener("turbo:render", restore)
document.addEventListener("turbo:frame-render", restore)
document.addEventListener("turbo:after-stream-render", restore)
