import AutocompleteBase from "controllers/autocomplete_base"

// Single-Value-Source-Picker für das bib_source-Feld der KI-Forms.
// Tippt der User eine Suche, fragt der Controller /sources/suggest?q=…
// ab und zeigt eine Liste {slug, title, creators}-Items. Auswahl
// schreibt den Slug ins Input. Slug-Anzeige + Title-Hint im Dropdown,
// damit man den Slug nicht auswendig kennen muss.
//
// Markup:
//   <div data-controller="source-picker"
//        data-source-picker-url-value="<%= suggest_sources_path %>">
//     <input data-source-picker-target="input" name="bib_source_slug" />
//     <ul data-source-picker-target="list" class="hidden …"></ul>
//   </div>
export default class extends AutocompleteBase {
  renderItem(item, isActive) {
    const cls = isActive ? "bg-emerald-50 text-emerald-900" : "hover:bg-slate-50"
    return `<li class="px-3 py-1.5 text-sm cursor-pointer ${cls}">
      <div class="flex items-baseline gap-2">
        <span class="font-mono text-xs text-slate-500 shrink-0">${this.escapeHtml(item.slug)}</span>
        <span class="truncate">${this.escapeHtml(item.label)}</span>
      </div>
      ${item.creators ? `<div class="text-xs text-slate-500 truncate">${this.escapeHtml(item.creators)}</div>` : ""}
    </li>`
  }

  commit(item) {
    if (!item) return
    this.inputTarget.value = item.slug
    this.close()
  }
}
