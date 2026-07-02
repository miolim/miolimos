import AutocompleteBase from "controllers/autocomplete_base"

// Autocomplete für komma-getrennte Slug-Felder (Themen, Kontakte).
//
// Das Feld hat value wie "patent-ring, mpg-solar". Der User tippt weiter,
// der Controller extrahiert das Segment nach dem letzten Komma vor dem
// Cursor als Suchbegriff, holt Treffer und zeigt eine Vorschlagsliste.
// Auswahl ersetzt das Segment durch <slug> und hängt ", " an.
//
// Erwartetes JSON: `{ items: [{ slug, label }] }`.
export default class extends AutocompleteBase {
  // Query ist das Segment zwischen letztem Komma und Cursor.
  queryFromInput() {
    const { value, selectionStart } = this.inputTarget
    const before = value.substring(0, selectionStart)
    const lastComma = Math.max(before.lastIndexOf(","), -1)

    let start = lastComma + 1
    while (start < before.length && /\s/.test(before[start])) start++

    this.segStart = start
    return before.substring(start).trim()
  }

  renderItem(item, isActive) {
    const cls = isActive ? "bg-emerald-50 text-emerald-900" : "hover:bg-slate-50"
    return `<li class="px-3 py-1.5 text-sm cursor-pointer ${cls}">
      <span class="font-mono text-slate-900">${this.escapeHtml(item.slug)}</span>
      <span class="text-xs text-slate-500 ml-2">${this.escapeHtml(item.label || "")}</span>
    </li>`
  }

  commit(item) {
    if (!item || this.segStart === null || this.segStart === undefined) return
    const value  = this.inputTarget.value
    const cursor = this.inputTarget.selectionStart
    const before = value.substring(0, this.segStart)
    const after  = value.substring(cursor)
    const sep    = after.startsWith(",") || after === "" ? "" : ", "
    const replacement = item.slug + sep
    const newValue = before + replacement + after
    this.inputTarget.value = newValue
    const newCursor = before.length + replacement.length
    this.inputTarget.setSelectionRange(newCursor, newCursor)
    this.inputTarget.focus()
    this.close()
  }
}
