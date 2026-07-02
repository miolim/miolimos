import AutocompleteBase from "controllers/autocomplete_base"

// Generischer Picker, um eine Entität (Topic, Contact, …) mit einem Parent
// (KnowledgeItem, Task, …) zu verbinden. Click/Focus öffnet ein Dropdown
// mit Vorschlägen, Tippen filtert. Letzte Zeile: `+ "<Eingabe>" anlegen`,
// wenn keine exakte Übereinstimmung. Submit (Klick/Enter) feuert POST
// an addUrl — der Server antwortet mit Turbo-Stream, der die Chips
// aktualisiert.
//
// Markup:
//   <div data-controller="entity-picker"
//        data-entity-picker-url-value="/topics/suggest"
//        data-entity-picker-add-url-value="/knowledge_items/<uuid>/topics"
//        data-entity-picker-param-name-value="topic_id"
//        data-entity-picker-create-label-value="anlegen">
//     <input data-entity-picker-target="input" placeholder="…">
//     <ul data-entity-picker-target="list" class="hidden …"></ul>
//   </div>
//
// Erwartetes JSON vom suggestUrl: `{ items: [{ slug, label }] }`. Der
// Server-Add nimmt entweder `<paramName>=<slug>` oder `create_with=<text>`.
export default class extends AutocompleteBase {
  static targets = ["input", "list", "trigger", "inputBox"]
  static values = {
    url:         String,
    addUrl:      String,
    paramName:   { type: String, default: "target_id" },
    createLabel: { type: String, default: "anlegen" },
    allowCreate: { type: Boolean, default: true },
    // #559 (Hans): Einzelwert-Picker (Projekt/Aussteller/Empfänger) schließen
    // nach der Auswahl, statt für den nächsten Eintrag offen zu bleiben.
    closeAfterPick: { type: Boolean, default: false }
  }

  // #389 (Hans, 2026-05-28): Icon/Trigger-Klick toggelt das Input:
  // Wenn die Eingabe schon offen ist, wieder ausblenden (Hans-Spec
  // „Icon wie Toggle-Schalter"). Sonst einblenden + fokussieren.
  // #603 R4 (Hans): ganze Zeile klickbar; interaktive Elemente ausgenommen.
  openFromRow(event) {
    if (event.target.closest("a, button, input, select, textarea, label, form")) return
    this.openInput(event)
  }

  openInput(event) {
    event?.preventDefault()
    // #559: funktioniert auch ohne Trigger-Button (icon_only) — dann ist
    // das Icon der einzige Toggle. Trigger nur mitschalten, wenn vorhanden.
    if (this.hasInputBoxTarget) {
      const isOpen = !this.inputBoxTarget.hidden
      if (isOpen) {
        // Toggle aus: Input weg, Trigger zurueck. Wert leeren, damit
        // beim naechsten Oeffnen keine alte Suche stehen bleibt.
        this.inputTarget.value     = ""
        this.inputBoxTarget.hidden = true
        this.element.classList.remove("erow-open")   // #603 R5
        if (this.hasTriggerTarget) this.triggerTarget.hidden = false
        if (typeof super.close === "function") super.close()
        return
      }
      if (this.hasTriggerTarget) this.triggerTarget.hidden = true
      this.inputBoxTarget.hidden = false
      this.element.classList.add("erow-open")   // #603 R5: Hover aus solange offen
    }
    // Eigene Blur-Logik anhaengen, einmal pro Connect: Wenn das Input
    // wirklich Focus verliert (kein anderes Picker-Element bekommt
    // ihn), Trigger zurueckblenden — sofern leer.
    if (this.hasInputTarget && !this._blurAttached) {
      this._blurAttached = true
      this.inputTarget.addEventListener("blur", () => {
        // Kurz warten, falls der Klick auf ein Dropdown-Item gerade
        // den Fokus weitergibt; AutocompleteBase verzoegert sein
        // close() auch um 150ms.
        setTimeout(() => {
          if (document.activeElement === this.inputTarget) return
          if (this.inputTarget.value) return
          if (!this.hasInputBoxTarget) return
          if (this.hasTriggerTarget) this.triggerTarget.hidden = false
          this.inputBoxTarget.hidden = true
        }, 180)
      })
    }
    this.inputTarget.focus()
    // Bei leerer Eingabe sofort Suggestions laden — Click auf Trigger
    // bedeutet „zeig mir die Optionen", auch ohne Tippen.
    this.onInput()
  }

  // Letzte Zeile als Sentinel anhängen, wenn eine Eingabe da ist und
  // kein exakter Treffer existiert. Wir benutzen `_create: true` als
  // Marker — commit prüft das und schickt `create_with` statt der ID.
  render() {
    const q = this.queryFromInput()
    const exact = q && this.suggestions.some(it =>
      (it.label || "").toLowerCase() === q.toLowerCase()
    )

    let items = this.suggestions
    if (q && !exact && this.allowCreateValue) {
      items = items.concat([{ _create: true, label: q }])
    }

    if (items.length === 0) { this.close(); return }
    this.listTarget.innerHTML = items
      .map((item, i) => this.wrapItem(item, i))
      .join("")
    this.listTarget.classList.remove("hidden")
    this._items = items
  }

  renderItem(item, isActive) {
    const cls = isActive ? "bg-emerald-50 text-emerald-900" : "hover:bg-slate-50"
    if (item._create) {
      return `<li class="px-3 py-1.5 text-sm cursor-pointer border-t border-slate-100 ${cls}">
        <span class="text-emerald-700">+</span> &quot;${this.escapeHtml(item.label)}&quot; ${this.escapeHtml(this.createLabelValue)}
      </li>`
    }
    return `<li class="px-3 py-1.5 text-sm cursor-pointer ${cls}">
      ${this.escapeHtml(item.label || "")}
      ${item.slug ? `<span class="ml-1 text-xs text-slate-400 font-mono">${this.escapeHtml(item.slug)}</span>` : ""}
    </li>`
  }

  pick(event) {
    event.preventDefault()
    const i = parseInt(event.currentTarget.dataset.autocompleteIndex, 10)
    this.commit(this._items[i])
  }

  onKeyDown(event) {
    if (!this.isOpen()) return
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.index = (this.index + 1) % this._items.length
      this.render()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.index = (this.index - 1 + this._items.length) % this._items.length
      this.render()
    } else if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault()
      this.commit(this._items[this.index])
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  async commit(item) {
    if (!item) return

    const body = new URLSearchParams()
    if (item._create) {
      body.set("create_with", item.label)
    } else if (item.slug) {
      body.set(this.paramNameValue, item.slug)
    } else if (item.id) {
      body.set(this.paramNameValue, item.id)
    } else {
      return
    }

    const res = await fetch(this.addUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: body.toString()
    })

    if (!res.ok) {
      console.warn("entity-picker add failed:", res.status)
      return
    }

    const html = await res.text()
    if (html && html.trim()) window.Turbo.renderStreamMessage(html)

    this.inputTarget.value = ""
    this.close()
    // #559: Einzelwert-Picker nach der Auswahl ganz schließen (zurück auf den
    // Trigger), sonst Fokus halten für den nächsten Eintrag (Many-to-Many).
    if (this.closeAfterPickValue && this.hasInputBoxTarget) {
      this.inputBoxTarget.hidden = true
      if (this.hasTriggerTarget) this.triggerTarget.hidden = false
    } else {
      this.inputTarget.focus()
    }
  }
}
