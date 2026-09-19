import { Controller } from "@hotwired/stimulus"

// immoOS #1658 R11 (Hans): „Können die Marker im Hilfetext als Highlighter
// funktionieren? Wenn man sie im Ansichts-Modus anklickt, werden sie in der
// geöffneten Card gehighlighted."
//
// Ein Klick auf eine Beschriftung oder ein Symbol im Hilfetext sucht das
// gemeinte Element in den offenen Karten und hebt es kurz hervor. Gesucht wird
// in dieser Reihenfolge:
//   :ui:      → das registrierte Bedienelement (data-ui-icon)
//   :icon:    → das Symbol (data-icon)
//   :bereich: → die Überschrift mit diesem Schlüssel (data-i18n-key)
//   sonst     → ein Element, dessen sichtbarer Text die Beschriftung IST
//
// Gesucht wird in den Karten NEBEN der Hilfe — in ihr selbst steht das Wort ja
// schon.
export default class extends Controller {
  static values = { dauer: { type: Number, default: 2500 } }

  zeigen(event) {
    const marker = event.target.closest("[data-hilfe-schluessel]")
    if (!marker) return

    event.preventDefault()
    const ziel = this._finden(marker.dataset.hilfeArt,
                              marker.dataset.hilfeSchluessel,
                              marker.textContent.trim())
    if (!ziel) {
      // #1658 R14 (Hans: „hebt gar nicht hervor"): Zwei verschiedene Lagen,
      // die sich für den Nutzer gleich anfühlen. Steht die Hilfe ALLEIN (sie
      // lässt sich über /help/<schlüssel> als eigene Seite öffnen), gibt es
      // überhaupt nichts zu zeigen — das ist keine Fehlfunktion, sondern eine
      // fehlende Card daneben. Die alte Meldung sagte das nicht.
      this._melden(this._nachbarkarten().length === 0
        ? window.t("hilfe.zeiger_allein")
        : window.t("hilfe.nicht_sichtbar"))
      return
    }

    // #1658 R12 (Hans): „Die Hervorhebung … wieder entfernen. Sie soll nicht
    // dauerhaft stehenbleiben." Beim zweiten Klick löschte ich zwar den Timer,
    // die Markierung des VORIGEN Ziels blieb aber stehen. Deshalb erst alles
    // aufräumen, dann markieren — und der Timer räumt ebenfalls alles ab.
    this._aufraeumen()
    // #1658 R16 (Hans): „Hier wird beim Klick auf den Marker ‚Gebäude' in der
    // Inhaltskarte nicht hervorgehoben." Das Ziel lag in einem anderen Reiter:
    // gefunden wurde es, nur zeigte die Card etwas anderes — eine Markierung
    // auf einer verborgenen Stelle sieht aus wie gar keine. Also erst den
    // Reiter öffnen, in dem die Stelle liegt.
    this._reiterOeffnen(ziel)
    ziel.scrollIntoView({ block: "center", behavior: "smooth" })
    ziel.classList.add("hilfe-gezeigt")
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._aufraeumen(), this.dauerValue)
  }

  _aufraeumen() {
    document.querySelectorAll(".hilfe-gezeigt").forEach((el) => el.classList.remove("hilfe-gezeigt"))
  }

  // Liegt die Stelle in einem verborgenen Reiter, wird dieser geöffnet — der
  // Reiter-Controller kann das von außen (`zeige`, aus #1566 R3). Zeigt der
  // Marker auf den REITER selbst, wird er ebenfalls geöffnet: Wer in der Hilfe
  // „Gebäude" anklickt, will den Gebäude-Reiter sehen, nicht nur sein Symbol.
  _reiterOeffnen(el) {
    if (el.matches?.('[data-simple-tabs-target="tab"]')) {
      const leiste = el.closest('[data-controller~="simple-tabs"]')
      const c = leiste && window.Stimulus?.getControllerForElementAndIdentifier(leiste, "simple-tabs")
      if (c && el.dataset.name) { c.zeige(el.dataset.name); return }
    }

    const panel = el.closest('[data-simple-tabs-target="panel"]')
    if (!panel || !panel.dataset.name) return

    const wurzel = panel.closest('[data-controller~="simple-tabs"]')
    if (!wurzel) return

    window.Stimulus?.getControllerForElementAndIdentifier(wurzel, "simple-tabs")?.zeige(panel.dataset.name)
  }

  // #1658 R16 (Hans): „Wenn es zwei identische Icons auf einer Karte gibt, kann
  // nicht das spezifische hervorgehoben werden … Wenn man in der Hilfe auf
  // eines klickt, wird nichts hervorgehoben." Sichtbares zuerst: Von mehreren
  // gleichen Symbolen ist das gemeint, das gerade auf dem Bildschirm steht.
  // Bleibt nur ein verborgenes übrig, wird es genommen — dann öffnet der
  // Aufrufer dessen Reiter.
  _sichtbar(el) {
    if (typeof el.checkVisibility === "function") return el.checkVisibility({ checkVisibilityCSS: true })
    return el.getClientRects().length > 0
  }

  // Wird die Hilfe-Card geschlossen, darf draußen nichts markiert bleiben.
  disconnect() {
    clearTimeout(this._timer)
    this._aufraeumen()
  }

  // Kurze Meldung im Toast-Stapel — dasselbe Muster wie im Beschriftungs-Modus.
  _melden(text) {
    const stapel = document.getElementById("toast_stack")
    if (!stapel) return

    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    const span = document.createElement("span")
    span.className = "flex-1 min-w-0"
    span.textContent = text
    div.appendChild(span)
    stapel.appendChild(div)
  }

  // Der Text, den das Element SELBST beisteuert — ohne den seiner Kinder.
  // Ohne das trifft keine Beschriftung, hinter der noch etwas steht („(optional)",
  // ein Zähler, ein Symbol); mit `children.length === 0` fiel sie ganz durch.
  _eigenerText(el) {
    return [...el.childNodes]
      .filter((n) => n.nodeType === Node.TEXT_NODE)
      .map((n) => n.textContent)
      .join(" ")
      .replace(/\s+/g, " ")
      .trim()
  }

  // Die Karten NEBEN der Hilfe — in ihr selbst steht das Wort ja schon.
  _nachbarkarten() {
    return [...document.querySelectorAll("article.stack-card")]
      .filter((c) => !String(c.dataset.uuid || "").startsWith("help:"))
  }

  _ausserhalbDerHilfe(el) {
    const karte = el.closest("article.stack-card")
    return !karte || !String(karte.dataset.uuid || "").startsWith("help:")
  }

  _finden(art, schluessel, text) {
    // #1658 R15 (Hans): „Bitte Such-/Filterfelder mit als Marker-Ziel
    // aufnehmen." Manche davon stehen NEBEN den Karten — die große Suche in der
    // Kopfleiste, Einträge der Seitenleiste. Deshalb zuerst die Nachbarkarten
    // (dort ist der Bezug am engsten) und danach der Rest der Seite, nur ohne
    // die Hilfe selbst: In ihr steht das gesuchte Wort ja schon.
    const karten = [...this._nachbarkarten(), document.body]
    const sicher = window.CSS?.escape ? CSS.escape(schluessel) : schluessel
    // In der Hilfe selbst darf nichts getroffen werden — sonst zeigt der Klick
    // auf das Wort, auf das er gerade gedrückt wurde.
    // #1658 R16 (Hans): „Wenn es zwei identische Icons auf einer Karte gibt,
    // kann nicht das spezifische hervorgehoben werden." Von mehreren gleichen
    // Zielen ist das gemeint, das gerade zu SEHEN ist — das erste im Markup
    // kann in einem anderen Reiter liegen. Ist keines sichtbar, wird das erste
    // genommen; dessen Reiter öffnet der Aufrufer dann.
    const suchen = (wurzel, wahl, pruefen = () => true) => {
      const alle = [...wurzel.querySelectorAll(wahl)]
        .filter((el) => this._ausserhalbDerHilfe(el) && pruefen(el))
      return alle.find((el) => this._sichtbar(el)) || alle[0]
    }

    for (const karte of karten) {
      if (art === "ui")      { const t = suchen(karte, `[data-ui-icon="${sicher}"]`); if (t) return t }
      if (art === "icon")    { const t = suchen(karte, `[data-icon="${sicher}"]`);    if (t) return t }
      // #1658 R14 (Hans: „hebt gar nicht hervor"): Der Schlüssel zuerst — seit
      // R12 tragen auch dt/label/th/legend ihren `data-i18n-key`. Vorher suchte
      // `:feld:` NUR über den sichtbaren Text; genau daran scheiterte
      // „Bezeichnung", weil auf der Grundstücks-Card „(optional)" als eigenes
      // Element dahinter steht und der Text deshalb nie exakt passte.
      if (art === "feld" || art === "bereich") {
        const benannt = suchen(karte, `[data-i18n-key="${sicher}"]`)
        if (benannt) return benannt
      }
      // Rückfall: was auf dem Bildschirm steht. Verglichen wird der EIGENE Text
      // des Elements (ohne den seiner Kinder) — „Bezeichnung (optional)" ist
      // ein <dt> mit einem <span> darin, und gemeint ist trotzdem das <dt>.
      if (art === "feld" || art === "bereich") {
        const treffer = suchen(karte, "label, th, dt, legend, summary, h1, h2, h3, h4, span, div, button, a",
                               (el) => this._eigenerText(el) === text)
        if (treffer) return treffer
        // #1658 R13 (Hans): Manche Felder tragen ihre Beschriftung nur als
        // Platzhalter im Eingabefeld — sichtbarer Text ist sie trotzdem. Das
        // sind vor allem die Such- und Filterfelder (R15).
        const feld = suchen(karte, "input[placeholder], textarea[placeholder]",
                            (el) => el.getAttribute("placeholder").trim() === text)
        if (feld) return feld
        // #1658 R16 (Hans): „… wird beim Klick auf den Marker ‚Gebäude' in der
        // Inhaltskarte nicht hervorgehoben." Die Reiter der Card sind
        // ICON-Reiter — ihr Name steht nur im Tooltip. Wer „Gebäude" schreibt,
        // meint den Reiter; ohne diese Stufe gab es dafür kein Ziel.
        const beschriftet = suchen(karte, "[title], [aria-label], [data-label]",
                                   (el) => [el.getAttribute("title"), el.getAttribute("aria-label"), el.dataset.label]
                                     .some((a) => (a || "").trim() === text))
        if (beschriftet) return beschriftet
      }
    }
    return null
  }
}
