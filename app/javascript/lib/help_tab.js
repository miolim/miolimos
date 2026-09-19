// immoOS #1658 Stufe 2: Welcher Reiter einer Card ist gerade offen?
//
// Gelesen wird das sichtbare Panel, nicht der Stimulus-Zustand: Ein Panel ohne
// `hidden` IST der offene Reiter — das gilt auch unmittelbar nach einem
// Re-Render, bevor simple-tabs wieder verbunden ist.
//
// Nur die äußerste Reiterleiste zählt. Reiter innerhalb eines Reiters (z. B.
// Wärme) unterteilen denselben Bereich und bekommen keinen eigenen
// Hilfe-Schlüssel.
export function offenerReiter(card) {
  const leiste = card?.querySelector?.('[data-controller~="simple-tabs"]')
  const panel = leiste?.querySelector?.(':scope > [data-simple-tabs-target="panel"]:not(.hidden)')
  const name = panel?.dataset?.name
  // Der Schlüssel landet in einer URL und in der Datenbank: dieselben Zeichen,
  // die HelpCard::KEY_RE hinter dem Punkt erlaubt.
  return /^[a-z0-9_]+$/.test(name || "") ? name : null
}

// `property` + Reiter `settlement` → `property.settlement`; ohne Reiter bleibt
// es beim Schlüssel der Karte.
export function hilfeSchluessel(basis, reiter) {
  const art = String(basis || "").split(".")[0]
  return reiter ? `${art}.${reiter}` : art
}

// ── immoOS #1665: die offene Hilfe folgt dem Reiter ────────────────────
//
// Hans: „Wechselt man den Reiter, bleibt die Card aber stehen; man muss erneut
// auf das Fragezeichen klicken." Seit Stufe 2 fror der Klick den Reiter ein,
// der GERADE offen war — wer danach wechselte, las die Hilfe zum vorherigen.
// Schlimmer als gar keine, weil nichts es anzeigte.

// Die Karten-ART einer Hilfe-Stack-ID: "help:property.details" → "property",
// "help:list:properties" → "list:properties". Der Reiter hängt hinter dem
// Punkt; Schlüssel selbst enthalten nie einen (HelpCard::KEY_RE).
export function hilfeBasis(stackId) {
  return String(stackId || "").replace(/^help:/, "").split(".")[0]
}

// Auf welche Hilfe soll umgeschaltet werden? `null` heißt: nichts zu tun —
// entweder ist zu dieser Karte gar keine Hilfe offen, oder es steht schon die
// richtige da. Ohne DOM und ohne Netz; das Nachladen macht der Stapel.
export function hilfeTauschZiel(basis, reiter, offeneHilfen) {
  if (!basis) return null
  const offen = (offeneHilfen || []).find((id) => hilfeBasis(id) === basis)
  if (!offen) return null

  const ziel = `help:${hilfeSchluessel(basis, reiter)}`
  return ziel === offen ? null : ziel
}
