// #1677 (aus immoOS 6ad257b6 uebernommen): Welcher Vorschlag gehört zu Position i?
//
// Die Liste im DOM ist eine Momentaufnahme. Zwischen ihrem Aufbau und dem
// Klick kann eine neue Suchantwort `suggestions` ersetzen oder das Schließen
// sie leeren — der Index zeigt dann auf eine andere Person oder ins Leere.
// Deshalb gilt, was gerendert wurde, und erst danach der aktuelle Stand.
export function sichtbaresItem(rendered, suggestions, i) {
  if (!Number.isInteger(i) || i < 0) return undefined
  const liste = Array.isArray(rendered) && rendered.length > 0 ? rendered : suggestions
  return Array.isArray(liste) ? liste[i] : undefined
}
