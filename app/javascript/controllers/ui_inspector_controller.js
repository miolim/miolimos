import { Controller } from "@hotwired/stimulus"

// #704 (Hans, 2026-06-15): Interface-Kommunikationshilfe — ein
// „Beschriftungs-Modus". Schalter an: Mouse-Over hebt das Element/den
// Bereich hervor und zeigt dessen Label; Klick kopiert das Label in die
// Zwischenablage (statt die normale Aktion auszulösen). Erleichtert es,
// eindeutig zu beschreiben, wovon man gerade spricht.
//
// Angezeigt/kopiert wird ein Breadcrumb-Pfad der Vorfahren-Kette, z.B.
// „Hauptfenster > Blade > Spine > Schließen". Jede Ebene: data-ui-label >
// aria-label/title > bekannter Strukturname (#704 R2, Hans). ESC, erneuter
// Klick auf den Schalter oder das Tastenkürzel (Cmd/Ctrl+.) beenden.
export default class extends Controller {
  connect() {
    this._onOver  = this._onOver.bind(this)
    this._onMove  = this._onMove.bind(this)
    this._onClick = this._onClick.bind(this)
    this._onKey   = this._onKey.bind(this)
    this._onActivator = this._onActivator.bind(this)
    this.active = false
    document.addEventListener("keydown", this._onActivator, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onActivator, true)
    if (this.active) this._stop()
  }

  toggle() { this.active ? this._stop() : this._start() }

  // immoOS #1658 R8 (Hans): „Wenn ich den Hilfetext bearbeite und dann auf
  // Beschriftungs-Modus klicke, wird die Bearbeitung sofort abgebrochen."
  //
  // Der Klick auf den Schalter nahm dem Schreibfeld den Fokus — das Autosave
  // feuerte, bevor der Modus überhaupt an war, und schloss den Editor. Ein
  // Werkzeug-Knopf darf den Fokus nicht wegnehmen; `preventDefault` auf
  // mousedown verhindert den Fokuswechsel, der Klick selbst bleibt.
  fokusHalten(event) { event.preventDefault() }

  // Cmd/Ctrl + .  schaltet den Modus überall um (Shortcut „egal", #704).
  _onActivator(e) {
    if (e.key === "." && (e.metaKey || e.ctrlKey)) {
      e.preventDefault()
      this.toggle()
    }
  }

  _start() {
    this.active = true
    this._imGriff = false
    // #1658 R7: Wer aus einem Schreibfeld heraus nachschlägt, will danach dort
    // weiterschreiben — Fokus merken und beim Beenden zurückgeben.
    const feld = document.activeElement
    this._feldZurueck = feld && /^(TEXTAREA|INPUT)$/.test(feld.tagName) ? feld : null
    document.documentElement.dataset.uiInspect = "on"
    this.element.classList.add("text-emerald-600", "bg-emerald-50")
    this.element.setAttribute("aria-pressed", "true")

    this._tip = document.createElement("div")
    this._tip.className = "fixed z-[9999] pointer-events-none px-2 py-1 rounded bg-slate-900 " +
      "text-white text-xs shadow-lg max-w-md leading-snug"
    this._tip.style.display = "none"
    document.body.appendChild(this._tip)

    document.addEventListener("pointerover", this._onOver, true)
    document.addEventListener("pointermove", this._onMove, true)
    document.addEventListener("click", this._onClick, true)
    document.addEventListener("keydown", this._onKey, true)
  }

  _stop() {
    this.active = false
    if (this._feldZurueck && document.contains(this._feldZurueck)) {
      const feld = this._feldZurueck
      // Nach dem Aufräumen: sonst nimmt der Modus den Fokus gleich wieder weg.
      setTimeout(() => feld.focus({ preventScroll: true }), 0)
    }
    this._feldZurueck = null
    delete document.documentElement.dataset.uiInspect
    this.element.classList.remove("text-emerald-600", "bg-emerald-50")
    this.element.setAttribute("aria-pressed", "false")

    document.removeEventListener("pointerover", this._onOver, true)
    document.removeEventListener("pointermove", this._onMove, true)
    document.removeEventListener("click", this._onClick, true)
    document.removeEventListener("keydown", this._onKey, true)

    this._clearHighlight()
    this._tip?.remove()
    this._tip = null
    this._current = null
  }

  _onKey(e) {
    if (e.key === "Escape") { e.preventDefault(); this._stop() }
  }

  _onOver(e) {
    const found = this._labelFor(e.target)
    this._highlight(found.el)
    this._current = found
    if (!this._tip) return

    // immoOS #1658 R8 (Hans): „Der Tooltip im Beschriftungsmodus sollte
    // anzeigen, was tatsächlich kopiert wird." Also nicht mehr der
    // Beschriftungspfad, sondern der Marker, den ein Klick hier erzeugt.
    //
    // Was ohne Rückfrage feststeht, steht sofort da; die Beschriftung braucht
    // den Server, deshalb erst der Text und gleich darauf der Marker.
    const sofort = this._markerOhneNachfrage(e.target)
    // Solange der Schlüssel noch nachgeschlagen wird, steht die ART schon fest
    // — den Beschriftungspfad kurz aufblitzen zu lassen wäre irreführend, denn
    // kopiert würde er nicht.
    const wartet = this._istBeschriftung(e.target)
      ? (e.target.closest?.("h1, h2, h3, h4, summary") ? ":bereich:…" : ":feld:…")
      : found.label
    this._tip.textContent = sofort || wartet
    this._tip.style.display = "block"
    if (!sofort) this._tipNachtragen(e.target, found.label)
  }

  // Sieht das aus wie eine Beschriftung? (Kurzer eigener Text, kein Eingabefeld.)
  _istBeschriftung(ziel) {
    const el = ziel.closest?.("label, th, summary, h1, h2, h3, h4, dt, span, div, button, a") || ziel
    const text = (el.textContent || "").trim()
    return text.length > 0 && text.length <= 60 && !el.querySelector?.("input, textarea, select")
  }

  // Bedienelement, Symbol und benannte Überschrift stehen im Markup — dafür
  // braucht es niemanden.
  _markerOhneNachfrage(ziel) {
    const ui = ziel.closest?.("[data-ui-icon]") || ziel.querySelector?.("[data-ui-icon]")
    if (ui) return `:ui:${ui.dataset.uiIcon}:`
    const symbol = ziel.closest?.("[data-icon]") || ziel.querySelector?.("[data-icon]")
    if (symbol) return `:icon:${symbol.dataset.icon}:`
    // #1658 R9: Abschnittsüberschriften nennen ihren Schlüssel selbst. Der
    // Nachschlag über den Text könnte hier nur raten — „Adresse" gibt es im
    // Programm zweimal, und die Karte benutzt den einen, nicht den anderen.
    const ueberschrift = ziel.closest?.("[data-i18n-key]") || ziel.querySelector?.("[data-i18n-key]")
    if (ueberschrift) return `:${this._markerArt(ueberschrift)}:${ueberschrift.dataset.i18nKey}:`
    return null
  }

  // Beschriftungen: nachschlagen, gebündelt und gemerkt. Beim Überfahren
  // vieler Elemente soll nicht jedes eine Anfrage auslösen.
  _tipNachtragen(ziel, ersatz) {
    clearTimeout(this._tipTimer)
    this._tipTimer = setTimeout(async () => {
      if (!this.active || this._current?.el !== this._labelFor(ziel).el) return

      const marker = await this._beschriftungsMarker(ziel, { still: true })
      if (this._tip && this.active) this._tip.textContent = marker || ersatz
    }, 200)
  }

  _onMove(e) {
    if (!this._tip) return
    const pad = 14
    let x = e.clientX + pad, y = e.clientY + pad
    const r = this._tip.getBoundingClientRect()
    if (x + r.width > window.innerWidth)   x = e.clientX - r.width - pad
    if (y + r.height > window.innerHeight) y = e.clientY - r.height - pad
    this._tip.style.left = `${Math.max(0, x)}px`
    this._tip.style.top  = `${Math.max(0, y)}px`
  }

  async _onClick(e) {
    // Klick auf den Schalter selbst NICHT abfangen (zum Ausschalten).
    if (this.element.contains(e.target)) return
    e.preventDefault()
    e.stopPropagation()
    e.stopImmediatePropagation()
    // immoOS #1658 R7 (Hans): „Bei Icons wird nicht die Funktion kopiert,
    // sondern der bisherige Pfad." Ursache gemessen: EIN Mausklick erzeugt hier
    // ZWEI Klick-Ereignisse (das zweite stammt aus dem Öffnen-Verhalten der
    // Oberfläche). Das Nachschlagen des ersten dauert einen Moment, der zweite
    // ist sofort fertig — und überschrieb die Zwischenablage mit dem
    // Beschriftungspfad. Der erste Klick gewinnt, alle weiteren prallen ab.
    if (this._imGriff) return

    this._imGriff = true
    // immoOS #1658 (Hans): „Könnte man eine Funktion haben, mit der man sie aus
    // der Card kopieren kann … um sie in der Hilfe einzusetzen?" Trägt das
    // angeklickte Element ein registriertes Bedienelement-Icon, kopieren wir
    // dessen Marker statt des Beschriftungspfads — fertig zum Einfügen.
    const iconEl = e.target.closest?.("[data-ui-icon]") || e.target.querySelector?.("[data-ui-icon]")
    if (iconEl) { await this._fertig(`:ui:${iconEl.dataset.uiIcon}:`); return }

    // #1658 R7: Symbole ohne registrierte Funktion — dann wenigstens das Bild
    // selbst, statt auf den Beschriftungspfad zurückzufallen.
    const symbol = e.target.closest?.("[data-icon]") || e.target.querySelector?.("[data-icon]")
    if (symbol) { await this._fertig(`:icon:${symbol.dataset.icon}:`); return }

    // #1658 R9: Überschrift mit hinterlegtem Schlüssel — exakt statt geraten.
    const ueberschrift = e.target.closest?.("[data-i18n-key]") || e.target.querySelector?.("[data-i18n-key]")
    if (ueberschrift) { await this._fertig(`:${this._markerArt(ueberschrift)}:${ueberschrift.dataset.i18nKey}:`); return }

    // #1658 R6: Feld- und Abschnittsbeschriftungen. Der Schlüssel steht nicht
    // im Markup — der Server schlägt ihn zum sichtbaren Text nach, gewichtet
    // nach der Karte, auf der geklickt wurde („Wohnungsfläche gesamt" gibt es
    // am Grundstück UND am Gebäude).
    const marker = await this._beschriftungsMarker(e.target)
    if (marker) { await this._fertig(marker); return }

    const label = (this._current && this._current.label) || this._labelFor(e.target).label
    await this._fertig(label)
  }

  // Kopieren und Modus beenden — Hans: „danach soll der Modus automatisch
  // wieder deaktiviert sein, damit man gleich weitertippen kann."
  async _fertig(text) {
    await this._copy(text)
    this._stop()
  }

  // #1677: Ein Element mit `data-i18n-key` ist nicht automatisch ein BEREICH. Im
  // Fork wurde jedes so zitiert (fett-kursiv) — seit dort auch Feld-Labels den
  // Schlüssel tragen, stimmte das für Felder nicht mehr. Überschriften und
  // <summary> sind Bereiche, alles andere ist ein Feld.
  _markerArt(element) {
    return element.closest?.("h1, h2, h3, h4, summary") ? "bereich" : "feld"
  }

  async _beschriftungsMarker(ziel, { still = false } = {}) {
    const el = ziel.closest?.("label, th, summary, h1, h2, h3, h4, dt, span, div, button, a") || ziel
    const text = (el.textContent || "").trim()
    if (!text || text.length > 60 || el.querySelector?.("input, textarea, select")) return null

    const art = ziel.closest?.("article.stack-card")?.dataset?.uuid?.split(":")[0] || ""
    const typ = ziel.closest?.("h1, h2, h3, h4, summary") ? "bereich" : "feld"
    // Gemerkt: Beim Überfahren fragt sonst jedes Element erneut nach.
    this._gemerkt ||= new Map()
    const merkschluessel = `${typ}|${art}|${text}`
    if (this._gemerkt.has(merkschluessel)) return this._gemerkt.get(merkschluessel)

    try {
      const url = `/help/bezeichnungen?text=${encodeURIComponent(text)}&bereich=${encodeURIComponent(art)}`
      const res = await fetch(url, { headers: { Accept: "application/json" } })
      if (!res.ok) return null
      const daten = await res.json()
      const treffer = daten.treffer || []
      if (treffer.length === 0) { this._gemerkt.set(merkschluessel, null); return null }
      if (treffer.length > 1 && !daten.eindeutig && !still) {
        // Mehrdeutig: Der erste passt zur Karte, aber sicher ist das nicht —
        // gesagt wird es trotzdem, damit niemand blind zitiert.
        this._toast(window.t("ui_inspector.mehrdeutig", { anzahl: treffer.length }))
      }
      const marker = `:${typ}:${treffer[0].schluessel}:`
      this._gemerkt.set(merkschluessel, marker)
      return marker
    } catch (err) {
      return null
    }
  }

  async _copy(label) {
    try {
      await navigator.clipboard.writeText(label)
      this._toast(window.t("ui_inspector.copied", { label: label }))
    } catch (err) {
      this._toast(window.t("ui_inspector.copy_failed"))
    }
  }

  // #704 (Hans): Breadcrumb-Pfad statt Einzel-Label — die Vorfahren-Kette
  // von außen nach innen, z.B. „Hauptfenster > Blade > Spine > Schließen".
  // Jede Ebene liefert ihren Namen via data-ui-label > aria-label/title >
  // bekannter Strukturname; so werden auch unspezifische Elemente eindeutig.
  _labelFor(el) {
    const parts = []
    let node = el
    // #1658 R7 (Hans): „bei Mouseover über eine Bezeichnung ein grüner Rahmen
    // … Bei Icons passiert das schon." Eine Beschriftung trägt weder
    // data-ui-label noch title — ohne diesen Anfang bliebe `leaf` leer und der
    // Rahmen sprang auf den nächsten benannten Vorfahren (die halbe Karte).
    let leaf = this._beschriftungsKnoten(el)
    while (node && node.nodeType === 1 && node !== document.body) {
      // Strukturname VOR aria-label/title — sonst zeigt z.B. der Spine den
      // (redundanten) Blade-Titel statt „Spine" (#704 R3, Hans).
      let label = (node.dataset && node.dataset.uiLabel) ||
                  this._structuralName(node) ||
                  node.getAttribute("aria-label") ||
                  node.getAttribute("title")
      label = label && String(label).trim()
      if (label && parts[parts.length - 1] !== label) {
        if (!leaf) leaf = node
        parts.push(label)
      }
      node = node.parentElement
    }
    if (parts.length === 0) parts.push(this._derive(el))
    return { el: leaf || el, label: parts.reverse().join(" > ") }
  }

  // Ein Blattknoten mit kurzem eigenem Text ist eine Beschriftung — genau das,
  // was der Klick nachschlägt. Also markieren wir beim Überfahren auch ihn.
  _beschriftungsKnoten(el) {
    if (!el || el.nodeType !== 1 || el.children.length > 0) return null
    const text = (el.textContent || "").trim()
    return text.length > 0 && text.length <= 60 ? el : null
  }

  // Bekannte Strukturelemente bekommen einen sprechenden Namen, ohne dass
  // jedes einzeln ein data-ui-label braucht.
  _structuralName(node) {
    if (!node.matches) return null
    if (node.matches("#blade_stack_container")) return window.t("ui_inspector.region_main_window")
    if (node.matches(".stack-card"))            return window.t("ui_inspector.region_card")
    if (node.matches(".stack-spine"))           return window.t("ui_inspector.region_spine")
    if (node.matches("turbo-frame"))            return null // Frames überspringen
    return null
  }

  _derive(el) {
    const host = el.closest && el.closest("[data-controller]")
    if (host) return host.dataset.controller.split(/\s+/)[0].replace(/[-_]/g, " ")
    return (el.id || (el.tagName || "element").toLowerCase())
  }

  _highlight(el) {
    if (this._hl === el) return
    this._clearHighlight()
    this._hl = el
    if (el && el.style) {
      this._prevOutline = el.style.outline
      this._prevOffset  = el.style.outlineOffset
      el.style.outline = "2px solid #10b981"
      el.style.outlineOffset = "-1px"
    }
  }

  _clearHighlight() {
    if (this._hl && this._hl.style) {
      this._hl.style.outline = this._prevOutline || ""
      this._hl.style.outlineOffset = this._prevOffset || ""
    }
    this._hl = null
  }

  _toast(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    const span = document.createElement("span")
    span.className = "flex-1 min-w-0"
    span.textContent = message
    const btn = document.createElement("button")
    btn.type = "button"
    btn.setAttribute("data-action", "click->toast#dismiss")
    btn.className = "text-slate-400 hover:text-white text-lg leading-none"
    btn.textContent = "×"
    div.append(span, btn)
    stack.appendChild(div)
  }
}
