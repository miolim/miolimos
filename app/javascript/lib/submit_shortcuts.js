// #451 (Hans, 2026-06-02): Tastatur-Shortcuts beziehen sich auf das
// GERADE AKTIVE Blade (Spine markiert, data-active="true") — nicht mehr
// nur auf den exakten Feld-Fokus. So greifen sie auch, wenn der Fokus
// nach einem Entwurf-Save o.ae. abhanden gekommen ist. Geteilt vom
// globalen submit-on-ctrl-enter-Controller (Plain-Felder / fokuslos) und
// der CM6-Mod-Enter/Mod-Shift-Enter-Keymap (CM6-Content ist kein
// <textarea>, der globale Handler greift dort nicht).
//
// Reihenfolge (von Hans):
//   Strg+Umschalt+Enter (am aktiven Blade):
//     1. Task im Entwurf/Pause       -> Veroeffentlichen
//     2. Antwort als Entwurf vorhanden -> Veroeffentlichen
//     3. Antwort in Bearbeitung (Compose hat Text) -> Senden
//   Strg+Enter:
//     - Fokus im Antwort-Compose     -> Als Entwurf speichern
//     - sonst Fokus in einem Edit-Form (Beschreibung/Body/Titel) -> Speichern
//     - sonst sichtbares Beschreibungs-Edit-Form am Blade -> Speichern

function submitForm(form) {
  if (typeof form.requestSubmit === "function") form.requestSubmit()
  else form.submit()
}

function composeText(form) {
  return (form.querySelector("textarea")?.value || "").trim()
}

// Klickt im Compose-Formular den Draft- bzw. Send-Button. Task- und
// KI-Replies nutzen `name="draft"` (value "1"=Entwurf, ""=Senden);
// aeltere Task-Comment-Forms `name="as_draft"`.
function clickCompose(form, draft) {
  const btns = Array.from(form.querySelectorAll('button[type="submit"], input[type="submit"]'))
  const draftBtn = btns.find(b => (b.name === "draft" || b.name === "as_draft") && b.value === "1")
  const sendBtn  = btns.find(b => b !== draftBtn)
  const target   = draft ? draftBtn : sendBtn
  if (target) target.click()
  else submitForm(form)
}

// Sichtbares (= im Edit-Mode geoeffnetes) Task-Beschreibungs-Form am Blade.
function visibleDescriptionForm(card) {
  return card.querySelector(
    'section[id^="task_description_"] form[data-description-toggle-target="form"]:not(.hidden)')
}

// Liefert das aktive Blade — bevorzugt das des fokussierten Elements,
// sonst das per data-active markierte.
function activeBlade(contextEl) {
  return contextEl?.closest?.(".stack-card")
      || document.querySelector('.stack-card[data-active="true"]')
}

export function dispatchBladeShortcut({ shiftKey, contextEl }) {
  const card = activeBlade(contextEl)
  if (!card) return false

  if (shiftKey) {
    // Strg+Umschalt+Enter — feste Reihenfolge.
    const taskPub = card.querySelector("[data-task-publish]")
    if (taskPub) { taskPub.click(); return true }

    const replyPub = Array.from(card.querySelectorAll("[data-reply-publish]")).pop()
    if (replyPub) { replyPub.click(); return true }

    const compose = card.querySelector("form[data-reply-compose]")
    if (compose && composeText(compose)) { clickCompose(compose, false); return true }
    return false
  }

  // Strg+Enter.
  // Fokus im Antwort-Compose -> Entwurf.
  const composeInFocus = contextEl?.closest?.("form[data-reply-compose]")
  if (composeInFocus) { clickCompose(composeInFocus, true); return true }

  // Fokus in einem anderen Edit-Form (Beschreibung/Body/Titel) -> Speichern.
  const editForm = contextEl?.closest?.("form")
  if (editForm) { submitForm(editForm); return true }

  // Fokus verloren: sichtbares Beschreibungs-Edit-Form am Blade speichern.
  const descForm = visibleDescriptionForm(card)
  if (descForm) { submitForm(descForm); return true }
  return false
}
