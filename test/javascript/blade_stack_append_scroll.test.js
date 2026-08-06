// #1283 (Hans): Beim Anhaengen einer Card soll der Stack stehenbleiben,
// solange die neue Card ohnehin ganz zu sehen ist. Vorher zog der
// Append-Pfad immer auf die Voll-Regal-Position und fuellte den
// Freiraum rechts aus.
// Laeuft ohne Build-Step/DOM: `node --test test/javascript/`.
import { test } from "node:test"
import assert from "node:assert/strict"
import { appendScrollTarget, BladeStackScrollMixin } from "../../app/javascript/lib/blade_stack_scroll.js"

const STEP = 28

// Vier Cards à 600px, Container 1600px: die neue (letzte) Card beginnt
// bei 1800 und endet bei 2400.
const vier = { cardX: 1800, cardW: 600, clientWidth: 1600, idx: 3, step: STEP }
// minScroll = 1800 + 600 - 1600 = 800   (Card rechtsbuendig)
// maxScroll = 1800 - 3*28     = 1716    (Card direkt rechts vom Stapel)

test("Stack steht rechts im Freiraum: Position bleibt, Platz bleibt offen", () => {
  // Genau Hans' Fall: der Stack ist ueber das Regal hinaus gescrollt, die
  // neue Card passt in den freien Streifen. Vorher sprang er auf 800.
  assert.equal(appendScrollTarget({ ...vier, current: 1000 }), 1000)
  assert.equal(appendScrollTarget({ ...vier, current: 1716 }), 1716)
})

test("neue Card ragt rechts heraus: minimal so weit, dass sie ganz sichtbar ist", () => {
  // Links im Stack — die Card laege ausserhalb, also muss gescrollt werden,
  // aber nur bis zur Kante (nicht weiter).
  assert.equal(appendScrollTarget({ ...vier, current: 0 }), 800)
  assert.equal(appendScrollTarget({ ...vier, current: 500 }), 800)
})

test("zu weit rechts: zurueck bis zur naeheren Grenze, nicht aufs Voll-Regal", () => {
  // Hier IST eine Korrektur noetig (die Card verschwindet sonst links
  // unter dem Sticky-Stapel) — aber nur bis maxScroll, nicht bis 800.
  assert.equal(appendScrollTarget({ ...vier, current: 2000 }), 1716)
})

test("Sub-Pixel-Rest an der Grenze loest keinen Ruck aus", () => {
  assert.equal(appendScrollTarget({ ...vier, current: 799.4 }), 799.4)
  assert.equal(appendScrollTarget({ ...vier, current: 1716.6 }), 1716.6)
})

test("erste Card im leeren Stack: nichts zu scrollen", () => {
  const allein = { cardX: 0, cardW: 600, clientWidth: 1600, idx: 0, step: STEP }
  assert.equal(appendScrollTarget({ ...allein, current: 0 }), 0)
})

test("Card passt nicht neben den Sticky-Stapel: null = alte Logik entscheidet", () => {
  // 33 Cards à 576 in 706px Container (Live-Fall aus #1167): der Stapel
  // ist breiter als der Platz neben der Card, es gibt keine Position, in
  // der sie vollstaendig frei steht.
  const eng = { cardX: 32 * 576, cardW: 576, clientWidth: 706, idx: 32, step: STEP }
  assert.equal(appendScrollTarget({ ...eng, current: 17000 }), null)
})

// Regressions-Riegel: der Regal-Fall darf NICHT zufaellig gruen sein,
// weil minScroll und die alte Voll-Regal-Position zusammenfallen.
test("die gehaltene Position unterscheidet sich wirklich vom Voll-Regal", () => {
  const gehalten = appendScrollTarget({ ...vier, current: 1200 })
  const vollRegal = vier.cardX + vier.cardW - vier.clientWidth
  assert.equal(gehalten, 1200)
  assert.notEqual(gehalten, vollRegal, "sonst prueft der Test nichts")
})

// ─── Verdrahtung: _scrollCardIntoFocus muss den neuen Weg nehmen ──────
// Die Regel oben nuetzt nichts, wenn der Append-Pfad sie nicht aufruft.
// Fake-Container statt DOM — der Mixin braucht nur Breiten und scrollLeft.
function fakeStack({ widths, clientWidth, scrollLeft, step = STEP }) {
  const cards = widths.map(w => ({ getBoundingClientRect: () => ({ width: w }) }))
  const container = {
    clientWidth,
    scrollLeft,
    dataset: { mobile: "false" },
    querySelectorAll: () => cards
  }
  const ctrl = Object.assign(Object.create(BladeStackScrollMixin), {
    containerTarget: container,
    constructor:     { SPINE_STEP: step },
    _stepEff:        step,
    // Fallback-Pfad markieren statt ihn auszufuehren.
    _scrollLastIntoView() { container.fallback = true }
  })
  return { ctrl, cards, container }
}

test("Append: schon sichtbare Card laesst die Position unangetastet", () => {
  const { ctrl, cards, container } = fakeStack({
    widths: [600, 600, 600, 600], clientWidth: 1600, scrollLeft: 1000
  })
  ctrl._scrollCardIntoFocus(cards.at(-1))
  assert.equal(container.scrollLeft, 1000, "kein Sprung aufs Voll-Regal")
  assert.ok(!container.fallback, "der alte Voll-Regal-Pfad darf hier nicht greifen")
})

test("Append: nicht sichtbare Card wird hereingeholt", () => {
  const { ctrl, cards, container } = fakeStack({
    widths: [600, 600, 600, 600], clientWidth: 1600, scrollLeft: 0
  })
  ctrl._scrollCardIntoFocus(cards.at(-1))
  assert.equal(container.scrollLeft, 800)
})

test("Append: passt die Card nicht neben den Stapel, greift die alte Logik", () => {
  const { ctrl, cards, container } = fakeStack({
    widths: Array(33).fill(576), clientWidth: 706, scrollLeft: 17000
  })
  ctrl._scrollCardIntoFocus(cards.at(-1))
  assert.ok(container.fallback, "_scrollLastIntoView muss uebernehmen")
})
