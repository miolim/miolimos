// #1653 (Hans): „Mir scheint es so, dass in letzter Zeit bei Antworten durch
// den Agenten die Card nicht mehr automatisch aktualisiert wird, sondern dass
// man aktiv einen Refresh machen muss."
//
// Gemessen auf Produktion: Der Live-Weg ist intakt — solange die Verbindung
// steht. Was FEHLT, ist das Nachholen: ActionCable spielt Nachrichten, die
// waehrend einer Unterbrechung gesendet wurden, NICHT nach. Jeder Deploy
// startet Puma neu und trennt dabei jede offene Verbindung; Ruhezustand und
// Netzwechsel tun dasselbe. Wird die Antwort in genau diesem Fenster gepostet
// (beim Agenten der Normalfall: Deploy, dann Kommentar), ist sie fuer die
// offene Card fuer immer verloren — bis der Nutzer neu laedt.
//
// Diese Datei enthaelt nur die Entscheidungen, ohne DOM — so sind sie ohne
// Browser testbar (test/javascript/live_resync.test.js).

// Die Verbindung gilt als WIEDERhergestellt, wenn sie vorher als getrennt
// bekannt war. Der erste Verbindungsaufbau (vorher unbekannt) zaehlt NICHT —
// sonst laedt jede frisch geoeffnete Card sofort ein zweites Mal.
export function istWiederverbunden(vorher, jetzt) {
  return vorher === false && jetzt === true
}

// Der Zaehler neben „Antworten" zeigt nichts, wenn es keine gibt.
export function zaehlertext(anzahl) {
  const n = Number(anzahl)
  return Number.isFinite(n) && n > 0 ? `· ${n}` : ""
}

// Nach einer Pause im Hintergrund lohnt das Nachladen nur, wenn die Pause
// lang genug war, um eine Nachricht verpasst haben zu koennen.
export function pauseWarLang(millisekunden, schwelle = 20000) {
  return Number(millisekunden) >= schwelle
}
