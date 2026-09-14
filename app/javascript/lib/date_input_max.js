// immoOS #1591 (Hans): „Wenn man sich bei den Jahreszahlen in den Datumfeldern
// vertippt und einfach weitertippt, um die bisherige Eingabe zu überschreiben,
// geht das nicht, weil man anscheinend eine 6-stellige Nummer eingeben kann,
// bevor man wieder von vorn beginnt."
//
// Das ist Browserverhalten: Ohne `max` erlaubt ein Datumsfeld Jahre bis 275760,
// das Jahressegment nimmt deshalb sechs Ziffern an. Mit einer Obergrenze im
// Jahr 9999 nimmt es vier und beginnt dann wieder von vorn.
//
// Einmal zentral statt an rund 80 Feldern in den Views: Jedes Datumsfeld OHNE
// eigenes `max` bekommt die Obergrenze — auch die, die Turbo nachlädt (Frames,
// Streams, Popover). Ein Feld mit eigenem `max` bleibt unberührt.
const OBERGRENZE = {
  date: "9999-12-31",
  "datetime-local": "9999-12-31T23:59",
  month: "9999-12"
}

const SELEKTOR = Object.keys(OBERGRENZE).map((typ) => `input[type="${typ}"]:not([max])`).join(",")

function begrenzen(wurzel) {
  if (!wurzel || typeof wurzel.querySelectorAll !== "function") return
  if (wurzel.matches?.(SELEKTOR)) wurzel.max = OBERGRENZE[wurzel.type]
  wurzel.querySelectorAll(SELEKTOR).forEach((feld) => { feld.max = OBERGRENZE[feld.type] })
}

function beobachten() {
  begrenzen(document.documentElement)
  new MutationObserver((mutationen) => {
    for (const m of mutationen) m.addedNodes.forEach(begrenzen)
  }).observe(document.documentElement, { childList: true, subtree: true })
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", beobachten, { once: true })
} else {
  beobachten()
}
