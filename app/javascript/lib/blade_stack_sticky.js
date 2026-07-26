// #1167 (Hans, 2026-07-26): Sticky-Offsets fuer den Card-Stapel als reine
// Funktion (test/javascript/blade_stack_sticky.test.js).
//
// Der feste SPINE_STEP (28px) liess die Spine-Stapel links (i*step) und
// rechts ((total-i)*step) unbegrenzt wachsen. Bei sehr vielen Cards wurde
// der Stapel breiter als der Viewport: die Pin-Plaetze der hinteren Cards
// lagen RECHTS der geklemmten letzten Card, deren Inhalt (hoechster
// z-Index) die nachrueckenden Spines verdeckte — rechts blieb ein Stueck
// Inhaltsbereich stehen, hinter dem die Spines verschwanden.
//
// Loesung: der Schritt schrumpft, sobald beide Stapel zusammen plus die
// breiteste Card nicht mehr in den Container passen —
//   stepEff = min(step, (clientWidth - maxCardWidth) / (total - 1)),
// nach unten begrenzt durch minStep (Spines bleiben greifbar, auch wenn
// der Stapel dann minimal ueberlaeuft). Damit gilt an jeder Fokus-
// Position: linker Stapel + offene Card + rechter Stapel <= Container.
//
// Die letzte Card wird wie bisher (#281 follow-up) links so geklemmt,
// dass sie vollstaendig ins Viewport passt.
export const SPINE_STEP_MIN = 4

export function stickyOffsets({ widths, clientWidth, step, minStep = SPINE_STEP_MIN }) {
  const total = widths.length
  if (total === 0) return { step: step, offsets: [] }
  const maxW    = Math.max(...widths)
  const budget  = Math.max(0, clientWidth - maxW)
  const stepEff = total > 1
    ? Math.min(step, Math.max(minStep, budget / (total - 1)))
    : step
  const offsets = widths.map((w, i) => {
    const naturalLeft = i * stepEff
    const left = i === total - 1
      ? Math.min(naturalLeft, Math.max(0, clientWidth - w))
      : naturalLeft
    return { left, right: (total - i) * stepEff - w, zIndex: i }
  })
  return { step: stepEff, offsets }
}
