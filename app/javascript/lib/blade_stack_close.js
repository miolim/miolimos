// #1091 (Hans, 2026-07-22): Focus-Nachfolge beim Schliessen von Cards.
//
// Als reine Funktion ausgelagert, damit die Regel ohne DOM testbar ist
// (test/javascript/blade_stack_close.test.js). Der Controller reicht die
// Card-Elemente durch; hier zaehlt nur ihre Reihenfolge im Stack.
//
// Hans-Spec:
//   * Hatte die geschlossene Card den Focus → naechste Card RECHTS davon,
//     sonst naechste Card LINKS davon.
//   * Hatte sie ihn nicht → die bisher fokussierte Card behaelt ihn
//     (Rueckgabe null = „nichts umsetzen").
//
// Ersetzt die Regel aus #358 (immer der linke Nachbar, egal wo der Focus
// war) — die verschob den Focus auch beim Schliessen einer beliebigen
// Hintergrund-Card.
export function focusTargetAfterClose(cards, closing, active) {
  if (!active || !closing.includes(active)) return null
  const closingIdx = closing.map(c => cards.indexOf(c)).filter(i => i >= 0)
  if (!closingIdx.length) return null
  const firstIdx = Math.min(...closingIdx)
  const lastIdx  = Math.max(...closingIdx)
  const remaining = cards.filter(c => !closing.includes(c))
  const right = remaining.find(c => cards.indexOf(c) > lastIdx)
  if (right) return right
  const left = remaining.filter(c => cards.indexOf(c) < firstIdx)
  return left.length ? left[left.length - 1] : null
}

// #1091 v2 (Hans, 2026-07-22): End-Spacer-Mathematik. Alles links der
// geschlossenen Card soll IMMER stehen bleiben — auch wenn rechts nicht
// genug Cards nachruecken, um den Platz zu fuellen, und auch beim
// Schliessen der letzten Card. Sonst klemmt der Browser scrollLeft an
// die geschrumpfte Scrollbreite und die links gestapelten Spines fahren
// wieder aus. Ein unsichtbarer Platzhalter am Stack-Ende haelt die
// Scrollbreite; sein Mass ist genau die Breite, die fehlt, damit die
// aktuelle Scrollposition gueltig bleibt.
//
// #1091 v3 (Hans, 2026-07-22): Der Freiraum ist ein ECHTER Ort — man kann
// nach rechts hinein- und wieder herausscrollen (v2 baute den Spacer beim
// Links-Scrollen ab; das ist raus). Beim Links-Scrollen fuellt er sich
// rein visuell, weil die Cards sich vor ihn schieben; schrumpfen tut er
// nur, wenn neue Cards angehaengt werden (Sync auf das aktuelle Mass)
// oder der Stack leer/mobil wird. Beim Schliessen waechst er hoechstens
// (grow-only), damit ein bestehender Freiraum nie kollabiert.
export function endSpacerWidth({ scrollLeft, clientWidth, contentWidth }) {
  return Math.max(0, scrollLeft + clientWidth - contentWidth)
}

// #1091 v4 (Hans, 2026-07-22): Der Freiraum entsteht auch durch REINES
// Scrollen, nicht nur durchs Schliessen. Der Stack erlaubt stehenden
// Overscroll bis zur „Voll-Regal"-Position: alle Cards links als Spines
// eingestapelt, nur die aeusserste rechte Card offen, rechts davon Leere.
// Der stehende Spacer misst genau die Breite, die dieser Endposition zum
// natuerlichen Content-Ende fehlt.
//   fullShelfScroll = X_last - stickyLeft_last (letzte Card exakt am
//   Pin-Platz), Spacer = fullShelfScroll + clientWidth - contentWidth.
export function standingSpacerWidth({ clientWidth, contentWidth, lastCardX, lastStickyLeft }) {
  return Math.max(0, lastCardX - lastStickyLeft + clientWidth - contentWidth)
}

// Wheel-Gesten sind Fokus-SCHRITTE (#224 6f-3); im Freiraum uebersetzen
// sie sich in Regal-Schritte: pro Geste rueckt EINE weitere Card in den
// linken Spine-Stapel (vorwaerts) bzw. wieder heraus (rueckwaerts) —
// kontinuierlich stufig, kein Snap ueber die ganze Leere. Die Stops sind
// die Scrollpositionen, an denen Card i genau an ihrem Sticky-Platz
// sitzt (X_i - stickyLeft_i).
export function nextShelfStop(stops, scrollLeft) {
  const next = stops.filter(p => p > scrollLeft + 1)
  return next.length ? Math.min(...next) : null
}

export function prevShelfStop(stops, scrollLeft) {
  const prev = stops.filter(p => p < scrollLeft - 1)
  return prev.length ? Math.max(...prev) : null
}
