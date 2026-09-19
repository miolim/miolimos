// #1677 (aus immoOS #1661 übernommen; Hans dort): „Es sollte einfach zwei Einträge geben: ‚Emma' Person
// anlegen / ‚Emma' Organisation anlegen. Erst bei Bestätigung eines der
// Einträge passiert die Anlage. Dann sollte die Person/Organisation auch als
// Card geöffnet werden."
//
// Diese Zeilen stehen inzwischen in zwei Auswahlfeldern (Einzelauswahl im
// Formular, Mehrfachauswahl im Fork). Was an ihnen entschieden wird —
// Wortlaut, Namenszerlegung, später eine Dublettenwarnung —, soll an EINER
// Stelle stehen; sonst driften die beiden auseinander, wie es die
// Namenszerlegung im Server schon einmal getan hat.

// Die Anlege-Zeilen, die unter die Treffer gehören: erst ab zwei Zeichen, und
// nicht, wenn ein Treffer den getippten Namen schon exakt trägt (dann ist die
// Suche erfolgreich gewesen — genau der Fall, für den es kein Anlegen braucht).
export function anlegeEintraege(q, suggestions, arten) {
  if (!q || q.length < 2) return []
  const exakt = suggestions.some((it) => (it.label || it.title || "").toLowerCase() === q.toLowerCase())
  if (exakt) return []
  return (arten && arten.length ? arten : ["person", "organization"]).map((art) => ({ _create: art, label: q }))
}

// Legt den Kontakt an und liefert { uuid, title, item_type } — oder null.
// Die Namenszerlegung steht bewusst NUR hier (Server: PersonKiResolver).
export async function personAnlegen(url, titel, art) {
  const body = new URLSearchParams()
  body.set("quick_create", "1")
  body.set("item_type", art)
  // FLACH, nicht `knowledge_item[title]` — die Schnellanlage liest `params[:title]`
  // und setzte sonst ihren Vorgabetitel („Neue Organisation"). Live aufgefallen:
  // Der Kontakt hieß nicht wie der getippte Name (#1661).
  body.set("title", titel)
  if (art === "person") {
    const teile = titel.trim().split(/\s+/)
    body.set("first_name", teile.length > 1 ? teile.slice(0, -1).join(" ") : "")
    body.set("last_name", teile[teile.length - 1])
  }

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
      "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
    },
    body
  })
  return res.ok ? res.json() : null
}

// „Dann sollte die Person/Organisation auch als Card geöffnet werden."
export function alsCardOeffnen(uuid) {
  if (!uuid) return
  window.dispatchEvent(new CustomEvent("blade-stack:append", {
    detail: { kind: "ki", id: uuid, oeffnen: "rechts" }
  }))
}
