import AutocompleteBase from "controllers/autocomplete_base"
import { anlegeEintraege, personAnlegen, alsCardOeffnen } from "lib/person_anlegen"

// #1677 (aus immoOS #1661 übernommen; Hans dort): „Stattdessen sollte es so sein, wie beim Hinzufügen
// einer Person im Detail-Bereich einer Aufgabe … Stattdessen sollte es einfach
// zwei Einträge geben: ‚Emma' Person anlegen / ‚Emma' Organisation anlegen.
// Erst bei Bestätigung eines der Einträge passiert die Anlage. Dann sollte die
// Person/Organisation auch als Card geöffnet werden."
//
// Anders als der entity-picker schreibt dieser hier NICHTS sofort weg: Er
// gehört in ein Formular, das erst am Ende abgeschickt wird (eine Beziehung
// mit Art und Zeitraum). Er füllt deshalb ein verstecktes
// Feld mit der Kennung und zeigt daneben den Namen.
export default class extends AutocompleteBase {
  static targets = ["input", "list", "uuid", "gewaehlt"]
  static values  = { url: String, createUrl: String, labels: Object, arten: Array, absenden: Boolean }

  connect() {
    super.connect()
    // Beim Umhängen steht der bisherige Name schon im Feld; die Kennung dazu
    // gilt nur so lange, wie der Name unverändert ist.
    this._gewaehlterName = this.inputTarget.value.trim()
    this._gespeichert    = this._gewaehlterName

    // Felder, die beim Verlassen von selbst speichern (Inline-Formulare),
    // dürfen das NICHT über ein `onblur` am Eingabefeld tun: Das Anlegen aus
    // der Liste ist ein Server-Aufruf und braucht einen Moment — der Blur wäre
    // vorher da und schickte den getippten Namen OHNE Kennung ab. Der Server
    // legte dann selbst an, und die Person stünde zweimal in der Liste.
    // Deshalb speichert hier der Picker: nach der Auswahl (dann steht die
    // Kennung schon im Feld) oder beim Verlassen, wenn gerade nichts läuft.
    if (this.absendenValue) this.inputTarget.addEventListener("blur", this._blurAbsenden.bind(this))
  }

  // Tippt jemand am gewählten Namen herum, ist die alte Kennung nicht mehr
  // gemeint — sonst würde der Server stillschweigend beim alten Kontakt
  // bleiben, obwohl im Feld längst ein anderer Name steht.
  onInput() {
    if (this.inputTarget.value.trim() !== this._gewaehlterName) this.uuidTarget.value = ""
    return super.onInput()
  }

  // Vorschläge plus die beiden Anlege-Zeilen — die erscheinen erst, wenn
  // getippt wurde und kein Vorschlag exakt passt.
  render() {
    const q = this.inputTarget.value.trim()
    const arten = this.hasArtenValue && this.artenValue.length ? this.artenValue : null
    const eintraege = this.suggestions.concat(anlegeEintraege(q, this.suggestions, arten))
    if (eintraege.length === 0) { this.close(); return }

    this.rendered = eintraege
    this.listTarget.innerHTML = eintraege.map((item, i) => this.wrapItem(item, i)).join("")
    this.listTarget.classList.remove("hidden")
  }

  renderItem(item, isActive) {
    const cls = isActive ? "bg-emerald-50 text-emerald-900" : "hover:bg-slate-50"
    if (item._create) {
      const was = this.labelsValue[item._create] || item._create
      return `<li class="px-2 py-1 text-[12px] cursor-pointer border-t border-slate-100 ${cls}">
        <span class="text-emerald-700">+</span> &quot;${this.escapeHtml(item.label)}&quot; ${this.escapeHtml(was)}
      </li>`
    }
    return `<li class="px-2 py-1 text-[12px] cursor-pointer ${cls}">${this.escapeHtml(item.label || "")}</li>`
  }

  async commit(item) {
    if (!item) return

    this._imGriff = true
    try {
      if (item._create) {
        const angelegt = await personAnlegen(this.createUrlValue, item.label, item._create)
        if (!angelegt) return
        this._uebernehmen(angelegt.uuid, angelegt.title)
        alsCardOeffnen(angelegt.uuid)
      } else {
        this._uebernehmen(item.slug || item.id, item.label)
      }
      this._absenden()
    } finally {
      this._imGriff = false
    }
  }

  _uebernehmen(uuid, titel) {
    this.uuidTarget.value = uuid || ""
    this.inputTarget.value = titel || ""
    this._gewaehlterName = (titel || "").trim()
    if (this.hasGewaehltTarget) this.gewaehltTarget.textContent = titel || ""
    this.close()
  }

  // Speichern heißt hier: das umgebende Inline-Formular abschicken. Nur, wenn
  // sich seit dem letzten Mal etwas geändert hat — sonst schriebe jedes
  // Anklicken des Feldes einen Datensatz.
  _absenden() {
    if (!this.absendenValue) return
    if (this.inputTarget.value.trim() === this._gespeichert) return

    this._gespeichert = this.inputTarget.value.trim()
    this.element.closest("form")?.requestSubmit()
  }

  // Der Blur kommt auch dann, wenn gerade ein Listeneintrag angeklickt wurde
  // (mousedown vor blur). Deshalb erst nach kurzer Frist und nur, wenn die
  // Auswahl nicht noch läuft.
  _blurAbsenden() {
    setTimeout(() => { if (!this._imGriff) this._absenden() }, 250)
  }
}
