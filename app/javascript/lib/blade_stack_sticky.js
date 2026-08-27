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
//
// #1167 v2 (Hans): Die AEUSSERSTE rechte Card behaelt beim Andocken am
// rechten Rand immer einen vollen step-Slot — ihr Ruecken muss als
// Ruecken lesbar bleiben, wenn sie beim Links-Scrollen einklappt. Mit
// dem geschrumpften Schritt dockte sie sonst als schmale Inhaltskante
// (~4px) an und wirkte „nicht ganz ausgeblendet". Nur die tieferen
// Stapel-Plaetze schrumpfen; bei stepEff == step ist die Formel
// identisch zur bisherigen ((total-i)*step - w).
export const SPINE_STEP_MIN = 4

export function stickyOffsets({ widths, clientWidth, step, minStep = SPINE_STEP_MIN }) {
  const total = widths.length
  if (total === 0) return { step: step, offsets: [] }
  const maxW    = Math.max(...widths)
  const budget  = Math.max(0, clientWidth - maxW - (total > 1 ? step : 0))
  const stepEff = total > 2
    ? Math.min(step, Math.max(minStep, budget / (total - 2)))
    : step
  const offsets = widths.map((w, i) => {
    const isLast = i === total - 1
    const naturalLeft = i * stepEff
    // #1487 (Hans): „Die Spines der folgenden Cards verschwinden hinter
    // dieser rechten Card, bis deren Spines den Bereich aufgefuellt haben."
    //
    // Die Klemmung aus #281 will, dass die letzte Card VOLLSTAENDIG ins
    // Viewport passt. Ist sie breiter als der Arbeitsbereich, ist das
    // unerreichbar — `Math.max(0, …)` machte daraus eine Klemmung auf 0.
    // Dann lag JEDER andere Pin-Platz (i * stepEff > 0) rechts von ihr,
    // und weil sie als letzte den hoechsten z-Index hat, deckte ihr
    // Inhalt die nachrueckenden Spines zu: genau das Bild aus #1167,
    // nur mit anderer Ursache. Bei 20 Cards und einer letzten, die
    // breiter ist als der Bereich, lagen 18 von 19 Plaetzen darunter.
    //
    // Passt sie nicht, wird sie deshalb GAR NICHT geklemmt: Sie behaelt
    // ihren normalen Stapel-Platz und laeuft nach rechts ueber — dorthin,
    // wo ohnehin gescrollt wird. Die Reihenfolge der Plaetze bleibt
    // monoton, und kein Spine verschwindet hinter Inhalt.
    //
    // Aktuell werden Cards zwischen 24rem und 60rem breit gerendert, und
    // die Breite laesst sich bis `innerWidth - 80` ziehen (gemerkt je
    // Card-Art im Browserspeicher). Eine Card, die breiter ist als der
    // Arbeitsbereich, ist also keine Ausnahme, sondern Alltag.
    const passt = clientWidth - w
    const left = isLast && passt > 0
      ? Math.min(naturalLeft, passt)
      : naturalLeft
    const right = isLast
      ? step - w
      : step + (total - 1 - i) * stepEff - w
    return { left, right, zIndex: i }
  })
  return { step: stepEff, offsets }
}
