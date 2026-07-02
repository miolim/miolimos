import TextareaAutocompleteBase from "lib/textarea_autocomplete_base"

// Obsidian-style Wikilink-Vorschlagsliste in einer Textarea: "[[" öffnet,
// Auswahl fügt "[[Titel]]" ein, Cursor landet dahinter.
// #564: Mechanik (Trigger/Fetch/Keyboard/Positionierung) lebt in
// lib/textarea_autocomplete_base — hier nur noch die Wikilink-Spezifika.
//
// Verwendung:
//   <div data-controller="wikilink-autocomplete"
//        data-wikilink-autocomplete-url-value="<%= suggest_knowledge_items_path %>">
//     <%= f.text_area :content, data: { wikilink_autocomplete_target: "input" } %>
//     <ul data-wikilink-autocomplete-target="list" class="hidden …"></ul>
//   </div>
export default class extends TextareaAutocompleteBase {
  triggerToken() { return "[[" }
  // Erst "]]" gilt als geschlossen — ein einzelnes "]" ist Teil des Titels.
  closeToken()   { return "]]" }

  // #667 (Hans): `[[@…` schlägt Personen-/Org-KIs vor und fügt
  // `[[@Name]]` ein; `[[…` ohne `@` schlägt alle Titel vor.
  extraParams(query) {
    return query.startsWith("@") ? "&item_type=person,organization" : ""
  }

  _isPerson() { return (this._lastQuery || "").startsWith("@") }

  renderItem(item, _isActive) {
    return this.escapeHtml(this._isPerson() ? `@${item.title}` : item.title)
  }

  insertion(item) {
    const label = this._isPerson() ? `@${item.title}` : item.title
    return { text: `[[${label}]]`, cursorOffset: 0 }
  }
}
