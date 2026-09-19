// immoOS #1658 R10 (Hans): „Kann das Rendering wie bei Antworten/Aufgaben
// greifen: Wenn der Cursor nicht beim Anker steht, dann wird gleich das Wort
// gerendert?"
//
// Dafür braucht der Editor, was nur der Server weiß: die Zeichnung zu einem
// Symbol und den Text zu einem Übersetzungsschlüssel. Beides wird genau für
// die im Dokument vorkommenden Marker geholt, gemerkt und nie zweimal
// angefragt. Ist die Antwort da, meldet ein Ereignis „neu zeichnen" — dasselbe
// Muster wie bei den Wikilink-Titeln (`cm6:wikilink-resolved`).
const symbole = new Map()       // Icon-Name        → SVG-Inhalt (oder null)
const elemente = new Map()      // Bedienelement    → SVG-Inhalt (oder null)
const bezeichnungen = new Map() // i18n-Schlüssel   → Text (oder null)
const laeuft = new Set()

function melden() {
  document.dispatchEvent(new CustomEvent("cm6:marker-resolved"))
}

async function holen(url, schluessel, ziel, auspacken) {
  const offen = schluessel.filter((s) => !ziel.has(s) && !laeuft.has(s))
  if (offen.length === 0) return

  offen.forEach((s) => laeuft.add(s))
  try {
    const res = await fetch(url(offen), { headers: { Accept: "application/json" } })
    const daten = res.ok ? auspacken(await res.json()) : {}
    // Auch das Nichtvorhandene merken — sonst fragt jeder Tastendruck erneut.
    offen.forEach((s) => ziel.set(s, daten[s] ?? null))
  } catch (err) {
    offen.forEach((s) => ziel.set(s, null))
  } finally {
    offen.forEach((s) => laeuft.delete(s))
    melden()
  }
}

export function symbol(name) {
  return symbole.get(name) ?? null
}

// `:ui:blade_copy:` nennt eine Funktion; welches Symbol sie trägt, weiß nur
// das Verzeichnis auf dem Server.
export function elementSymbol(schluessel) {
  return elemente.get(schluessel) ?? null
}

export function bezeichnung(key) {
  return bezeichnungen.get(key) ?? null
}

export function bekannt(sammlung, schluessel) {
  const karte = sammlung === "symbol" ? symbole : sammlung === "element" ? elemente : bezeichnungen
  return karte.has(schluessel)
}

export function nachladen({ symbolNamen = [], elementSchluessel = [], textSchluessel = [] }) {
  if (symbolNamen.length) {
    holen((n) => `/help/symbole?namen=${encodeURIComponent(n.join(","))}`,
          symbolNamen, symbole, (d) => d.symbole || {})
  }
  if (elementSchluessel.length) {
    holen((e) => `/help/symbole?elemente=${encodeURIComponent(e.join(","))}`,
          elementSchluessel, elemente, (d) => d.elemente || {})
  }
  if (textSchluessel.length) {
    holen((k) => `/help/bezeichnungen?keys=${encodeURIComponent(k.join(","))}`,
          textSchluessel, bezeichnungen, (d) => d.texte || {})
  }
}
