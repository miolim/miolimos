import TextareaAutocompleteBase from "lib/textarea_autocomplete_base"

// Pandoc-Cite-Vorschlag: "[@" in einer Textarea öffnet eine Liste passender
// Sources; Auswahl fügt "[@slug]" ein, Cursor landet VOR dem "]", damit man
// direkt mit ", S. 33" weitertippen kann.
// #564: Mechanik lebt in lib/textarea_autocomplete_base — hier nur noch
// die Cite-Spezifika.
//
// Verwendung:
//   <div data-controller="cite-autocomplete"
//        data-cite-autocomplete-url-value="<%= suggest_sources_path %>">
//     <textarea data-cite-autocomplete-target="input">…</textarea>
//     <ul data-cite-autocomplete-target="list" class="hidden …"></ul>
//   </div>
export default class extends TextareaAutocompleteBase {
  triggerToken() { return "[@" }

  // Komma in der Query → User schreibt schon den Locator (", S. 33").
  queryBlocked(query) {
    return super.queryBlocked(query) || query.includes(",")
  }

  renderItem(item, _isActive) {
    const creators = item.creators
      ? `<div class="text-xs text-slate-500 truncate">${this.escapeHtml(item.creators)}</div>` : ""
    return `
      <div class="flex items-baseline gap-2">
        <span class="font-mono text-xs text-slate-500 shrink-0">@${this.escapeHtml(item.slug)}</span>
        <span class="truncate">${this.escapeHtml(item.label)}</span>
      </div>${creators}`
  }

  insertion(item) {
    // Cursor vor dem schließenden ] (cursorOffset -1).
    return { text: `[@${item.slug}]`, cursorOffset: -1 }
  }
}
