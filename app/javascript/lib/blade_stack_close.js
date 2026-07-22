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
export function endSpacerWidth({ scrollLeft, clientWidth, contentWidth }) {
  return Math.max(0, scrollLeft + clientWidth - contentWidth)
}

// Der Freiraum wird beim Links-Scrollen kontinuierlich aufgefuellt,
// nicht per Snap: pro Scroll-Schritt schrumpft der Spacer um genau die
// nach links gescrollte Distanz (Rechts-Scrollen laesst ihn in Ruhe).
// So bleibt waehrend des Scrollens alles Sichtbare an Ort und Stelle,
// aber zurueck nach rechts in die Leere scrollen kann man nicht mehr.
export function spacerWidthAfterScroll(width, prevScrollLeft, scrollLeft) {
  return Math.max(0, width - Math.max(0, prevScrollLeft - scrollLeft))
}
