// #1114 (Hans, 2026-07-22): Rueckmeldung fuer Autosave-Felder.
//
// Autosave-Felder speichern per Inline-Handler (`onchange`/`onblur` →
// this.form.requestSubmit()) — 71 Stellen in 28 Views. Statt alle
// Call-Sites umzubauen, erkennt EIN globaler Controller
// (autosave_feedback_controller.js, gemountet am <body>) diese Felder
// an ihrem Inline-Handler und haengt die Rueckmeldung an: gruenes
// Haekchen (600 ms) bei Erfolg, roter Rahmen bei Fehler.
//
// Hier liegen die DOM-armen Helfer, testbar ohne Browser
// (test/javascript/autosave_feedback.test.js).

// Ist das Element ein Autosave-Ausloeser? Kennzeichen ist der
// vorhandene Inline-Handler — dieselbe Quelle, die auch das Speichern
// ausloest; es kann also nicht driften.
export function isAutosaveTrigger(el) {
  if (!el || typeof el.getAttribute !== "function") return false
  const handlers = (el.getAttribute("onchange") || "") + (el.getAttribute("onblur") || "")
  return handlers.includes("requestSubmit")
}

// Identitaet eines Feldes UNABHAENGIG vom DOM-Knoten: viele Autosave-
// Antworten ersetzen den Felder-Block per Turbo-Stream — der Knoten,
// der den Save ausgeloest hat, ist beim Feedback u.U. schon aus dem
// Dokument. Form-action + Feldname finden das Nachfolger-Element.
export function fieldDescriptor(form, field) {
  return {
    formAction: (form && typeof form.getAttribute === "function" && form.getAttribute("action")) || "",
    name:       (field && typeof field.getAttribute === "function" && field.getAttribute("name")) || ""
  }
}

// Nachfolger-Element eines ersetzten Feldes finden (oder null).
export function refindField(root, { formAction, name }) {
  if (!name) return null
  const forms = Array.from(root.querySelectorAll("form"))
  for (const form of forms) {
    if (((form.getAttribute && form.getAttribute("action")) || "") !== formAction) continue
    const candidates = Array.from(form.querySelectorAll("[name]"))
    const hit = candidates.find(el => el.getAttribute("name") === name)
    if (hit) return hit
  }
  return null
}

// #1496 (aus immoos #1457 R2 uebernommen). Hans dort: „Das haben wir gerade,
// wenn man von einem Auswahlfeld zum naechsten geht und gleich weiter tippt.
// Es ist sogar die Regel, dass das erste Feld dann noch nicht gespeichert ist
// und man wieder rausfliegt und neu anfangen muss zu tippen."
//
// Gerettet wurde bisher nur der ORT des Cursors, nicht der INHALT: Nach dem
// Austausch steht der Cursor richtig, das Getippte ist weg. Diese Funktion
// beantwortet die eine heikle Frage dabei — darf der Wert des Nutzers den des
// Servers ueberschreiben?
//
// Drei Lagen, und nur in zweien gewinnt der Nutzer:
//
//   1. Der Server hat das Feld NICHT angefasst (er liefert denselben Wert,
//      mit dem er es vorher gerendert hat). Dann ist das Getippte das Neuere
//      — es gewinnt.
//   2. Der Nutzer hat WEITERGETIPPT: Der Serverwert ist ein Anfang des
//      Getippten. Das ist der Fall, wenn ein Save mitten in der Eingabe lief
//      („Mül" gespeichert, inzwischen steht „Müller" da).
//   3. Sonst hat der Server wirklich etwas anderes gesetzt — er formatiert
//      Betraege, fuellt abhaengige Felder, rechnet nach. Dann gewinnt ER,
//      sonst ueberschreibt die Rettung eine Korrektur und der Nutzer sieht
//      seinen halben Text statt der richtigen Antwort.
export function darfWertZurueck(feld, merk) {
  if (!feld || !merk || typeof merk.wert !== "string") return false
  if (typeof feld.defaultValue !== "string") return false   // SELECT u. a.
  if (feld.value === merk.wert) return false                // steht schon da

  if (feld.defaultValue === merk.geliefert) return true     // Lage 1
  return merk.wert.startsWith(feld.value)                   // Lage 2
}
