import AutocompleteBase from "controllers/autocomplete_base"

// Read-only Title-Suggester. Bei Tippen im Title-Feld zeigt eine Liste
// existierender Titel mit Icon. Reines Hinweis-UI — kein Submit, kein
// Übernahme. Soll Dubletten verhindern und sichtbar machen, was schon
// im Bestand ist.
//
// Markup:
//   <div data-controller="title-suggest"
//        data-title-suggest-url-value="/knowledge_items/suggest">
//     <input data-title-suggest-target="input">
//     <ul data-title-suggest-target="list"></ul>
//   </div>
export default class extends AutocompleteBase {
  renderItem(item, isActive) {
    const cls = isActive ? "bg-emerald-50" : "hover:bg-slate-50"
    return `<li class="px-3 py-1.5 text-sm flex items-center gap-2 ${cls}">
      <a href="/knowledge_items/${this.escapeHtml(item.uuid)}"
         class="flex-1 truncate text-emerald-700 hover:underline"
         target="_blank" rel="noopener">
        ${this.escapeHtml(item.title)}
      </a>
    </li>`
  }

  // Click auf einen Vorschlag soll den Link folgen, kein commit().
  // Wir überschreiben die default-pick-Action: Standard-Browser-Click
  // auf den `<a>` zulassen, Dropdown nur schließen.
  pick(event) {
    if (event.target.closest("a")) {
      this.close()
      return
    }
    event.preventDefault()
  }

  // Enter im Title-Feld submittet das Form (nicht ein Vorschlag).
  // ArrowKeys deaktivieren wir hier — nichts zum "Auswählen".
  onKeyDown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  commit(_item) {
    // No-op — Suggest ist read-only.
  }
}
