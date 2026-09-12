import { Controller } from "@hotwired/stimulus"
import { composeHeight, spacerHeight, scrollTopForCaret } from "lib/sticky_compose"

// #1572 (Hans, 2026-09-12): Das Antwort-Feld klebt am unteren Rand der
// Card. Wer auf einzelne Punkte einer laengeren Antwort eingeht, musste
// bisher zwischen Zitat und Eingabefeld hoch- und runterscrollen (oder
// die Card duplizieren).
//
// Mechanik:
//   * Das Form ist `position: sticky; bottom: 0`. Klebe-Strecke ist der
//     umgebende Kasten — das disclosure-content-Div, also der ganze
//     Antworten-Bereich. Ueber dessen Oberkante hinaus (Aufgaben-
//     beschreibung, KI-Text) klebt es bewusst nicht mit.
//   * Beim Hochscrollen schrumpft der Editor um genau den Teil, der
//     unter die Card-Kante gerutscht waere, bis auf `minRows` Zeilen.
//   * Ein per JS eingehaengter Platzhalter direkt hinter dem Form
//     gleicht die abgegebene Hoehe im Fluss aus. Ohne ihn wuerde die
//     Card beim Schrumpfen kuerzer, die Scroll-Position verschoebe
//     sich, die naechste Messung ergaebe eine andere Hoehe — das Feld
//     zittert.
//
// Die Rechnung selbst steht in lib/sticky_compose.js und ist dort mit
// `node --test` abgedeckt; hier bleibt nur das Messen und Setzen.
//
// Ohne CodeMirror (`?cm6=0`) bleibt der Controller untaetig, das Feld
// verhaelt sich dann wie vorher.
export default class extends Controller {
  static values = { minRows: { type: Number, default: 2 } }

  connect() {
    this.mountSpacer()

    this.scroller = this.findScrollContainer()
    this._tick = () => this.schedule()
    this.scroller?.addEventListener("scroll", this._tick, { passive: true })
    window.addEventListener("scroll", this._tick, { passive: true })
    window.addEventListener("resize", this._tick)
    // CM6 dispatcht bei jeder Aenderung ein synthetisches input-Event
    // auf der versteckten Textarea (siehe cm6_editor_controller) — das
    // bubbelt hier hoch und ist unser Signal fuer „Inhalt gewachsen“.
    this.element.addEventListener("input", this._tick)

    // CM6 haengt seinen Editor erst in seinem eigenen connect() ein;
    // die Reihenfolge zweier Stimulus-Controller ist nicht garantiert.
    this.watcher = new MutationObserver(() => { if (this.editor) this.schedule() })
    this.watcher.observe(this.element, { childList: true, subtree: true })

    // Faengt alles, was keine eigenen Events hat: aufgeklappte
    // disclosure, Breitenaenderung der Card (Umbruch aendert die
    // Inhaltshoehe), Schriftgroessen-Wechsel.
    this.sizes = new ResizeObserver(() => this.schedule())
    this.sizes.observe(this.element)

    this.schedule()
  }

  disconnect() {
    this.scroller?.removeEventListener("scroll", this._tick)
    window.removeEventListener("scroll", this._tick)
    window.removeEventListener("resize", this._tick)
    this.element.removeEventListener("input", this._tick)
    this.watcher?.disconnect()
    this.sizes?.disconnect()
    if (this.frame) cancelAnimationFrame(this.frame)
    this.spacer?.remove()
  }

  // Der Platzhalter haengt als Geschwister hinter dem Form. Ein
  // Turbo-Morph der Card (Live-Update einer Antwort) kann ihn als
  // unbekanntes Element entfernen — dann haengen wir ihn neu ein,
  // sonst waere der Anker weg und das Feld schrumpfte nie mehr.
  mountSpacer() {
    if (!this.spacer) {
      this.spacer = document.createElement("div")
      this.spacer.setAttribute("aria-hidden", "true")
      // `space-y-*` am Container wuerde dem Platzhalter sonst einen
      // eigenen Abstand geben und den Anker verschieben.
      this.spacer.style.marginTop = "0"
      this.spacer.style.height    = "0px"
    }
    if (this.spacer.previousElementSibling !== this.element) this.element.after(this.spacer)
  }

  schedule() {
    if (this.frame) return
    this.frame = requestAnimationFrame(() => { this.frame = null; this.apply() })
  }

  get editor() { return this.element.querySelector(".cm-editor") }

  apply() {
    const editor = this.editor
    if (!editor || !this.scroller) return
    this.mountSpacer()
    const content = editor.querySelector(".cm-content")
    // Zugeklappte disclosure (oder Card noch nicht im Layout): messen
    // wuerde 0 ergeben und das Feld unsichtbar setzen. Der
    // ResizeObserver holt es nach, sobald es wieder Groesse hat.
    if (!content || !content.offsetHeight) return

    const cs      = getComputedStyle(content)
    const es      = getComputedStyle(editor)
    const borderY = (parseFloat(es.borderTopWidth) || 0) + (parseFloat(es.borderBottomWidth) || 0)
    const padY    = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0)
    const line    = parseFloat(cs.lineHeight) || 22

    // `.cm-content` ist so hoch wie das Dokument — unabhaengig davon,
    // welche Hoehe wir dem Editor gerade gegeben haben. Damit ist die
    // Messung frei von Rueckkopplung.
    const fullHeight = content.offsetHeight + borderY
    const minHeight  = line * this.minRowsValue + padY + borderY

    const height = composeHeight({
      fullHeight, minHeight,
      anchorBottom: this.spacer.getBoundingClientRect().bottom,
      viewBottom:   this.viewBottom()
    })

    const before = this.height
    this.height  = Math.round(height)
    editor.style.height      = `${this.height}px`
    this.spacer.style.height = `${Math.round(spacerHeight({ fullHeight, height }))}px`

    // Sichtbarer Hinweis, dass das Feld haftet statt mitzuscrollen.
    const docked = this.height < Math.round(fullHeight) - 0.5
    this.element.style.boxShadow = docked ? "0 -6px 10px -8px rgba(15, 23, 42, 0.35)" : ""

    if (before !== this.height) this.keepCaretVisible(editor)
  }

  // Wird das Feld kleiner, sollen die sichtbaren Zeilen die mit dem
  // Cursor sein — nicht die ersten des Entwurfs.
  keepCaretVisible(editor) {
    if (!editor.classList.contains("cm-focused")) return
    const scroller = editor.querySelector(".cm-scroller")
    const caret    = editor.querySelector(".cm-cursor-primary")
    if (!scroller || !caret) return

    const sr = scroller.getBoundingClientRect()
    const cr = caret.getBoundingClientRect()
    scroller.scrollTop = scrollTopForCaret({
      caretTop:     cr.top - sr.top + scroller.scrollTop,
      caretHeight:  cr.height,
      scrollTop:    scroller.scrollTop,
      clientHeight: scroller.clientHeight
    })
  }

  // Untere Kante des sichtbaren Bereichs. Beim Dokument-Scroll ist die
  // Elementkante die Dokument-Unterkante und damit unbrauchbar — dann
  // zaehlt das Fenster.
  viewBottom() {
    return Math.min(this.scroller.getBoundingClientRect().bottom, window.innerHeight)
  }

  // Die Card scrollt fuer sich (`overflow-y-auto`). Ausserhalb des
  // Stapels — Ansichten, in denen die Seite selbst scrollt — muss der
  // Rueckfall das Dokument sein: sonst klebt das Feld per CSS am Rand,
  // ohne dass es je jemand schrumpft.
  findScrollContainer() {
    let el = this.element.parentElement
    while (el) {
      const o = getComputedStyle(el).overflowY
      if (o === "auto" || o === "scroll") return el
      el = el.parentElement
    }
    return document.scrollingElement || document.documentElement
  }
}
