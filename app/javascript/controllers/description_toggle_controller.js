import { Controller } from "@hotwired/stimulus"

// Task-Beschreibung: schaltet zwischen Preview (gerenderter Markdown)
// und Edit (Textarea) um. Server liefert nach Save den Partial im
// Preview-Mode zurück (via Turbo-Stream), sodass nach onblur-Submit
// automatisch die Vorschau aktualisiert ist (#139).
//
// Mode-Wert (preview|edit) wird via data-Value initial gesetzt;
// edit-Button-Klick öffnet Edit, Blur auf Textarea submitet die Form,
// danach kommt der frische Preview-Partial vom Server.
export default class extends Controller {
  static targets = ["preview", "form", "input", "editBtn", "saveBtn"]
  static values  = { mode: { type: String, default: "preview" } }

  edit() {
    // #315 (Hans, 2026-05-25): Scroll-Position des umgebenden Scroll-
    // Containers merken; ohne das scrollt der Browser nach dem Toggle
    // den Edit-Bereich an den oberen Rand (Auto-Scroll-on-Focus) und
    // der User verliert seine Stelle in einer langen Beschreibung.
    const scroller = this._scrollContainer()
    const savedTop = scroller ? scroller.scrollTop : null

    this.previewTarget.classList.add("hidden")
    this.editBtnTarget.classList.add("hidden")
    this.saveBtnTarget.classList.remove("hidden")
    this.formTarget.classList.remove("hidden")
    // #748 (Hans, 2026-06-21): War die Beschreibungs-Sektion eingeklappt,
    // beim Wechsel in den Edit-Modus automatisch aufklappen — sonst liegt
    // die Textarea im versteckten disclosure-content und der User sieht
    // (und erreicht) das Bearbeiten-Feld nicht. disclosure sitzt am selben
    // <section>-Element; expand() ist idempotent.
    this.application
        .getControllerForElementAndIdentifier(this.element, "disclosure")
        ?.expand()
    // Fokus mit Cursor am Ende. value-trick ist robuster als
    // setSelectionRange (manche Browser ignorieren das auf hidden→shown).
    // #315 (Hans): preventScroll, damit der Browser nach unserem
    // Scroll-Restore unten nicht auf den Textarea-Top zurueckscrollt.
    this.inputTarget.focus({ preventScroll: true })
    const v = this.inputTarget.value
    this.inputTarget.value = ""
    this.inputTarget.value = v

    // Layout flush + Scroll restaurieren. requestAnimationFrame, damit
    // die Browser-Layout-Phase des hidden→shown Toggles abgeschlossen
    // ist (Textarea hat ihre Hoehe gemessen via field-sizing:content).
    if (scroller && savedTop !== null) {
      requestAnimationFrame(() => {
        scroller.scrollTop = savedTop
      })
    }
  }

  // Naechster scroll-faehiger Vorfahre. Wir suchen jeden Container mit
  // overflow-y auto|scroll; der Stack-Card-Body hat overflow-y-auto.
  _scrollContainer() {
    let el = this.element.parentElement
    while (el) {
      const cs = getComputedStyle(el)
      if (/(auto|scroll)/.test(cs.overflowY)) return el
      el = el.parentElement
    }
    return null
  }

  // Speichern-Button: zwei Effekte gleichzeitig.
  //
  //   1. Optimistic-UI: SOFORT in den Preview-Mode wechseln, damit der
  //      User unmittelbares Feedback bekommt. Der Server-Turbo-Stream
  //      ersetzt das Partial gleich darauf nochmal mit der frisch
  //      gerenderten Beschreibung — was im Fehlerfall den optimistischen
  //      Zustand wieder revertieren würde.
  //   2. onblur disarmen, damit das gleichzeitig feuernde Blur-Event
  //      nicht zusätzlich requestSubmit aufruft (sonst zwei PATCHes).
  //
  // mousedown + preventDefault: ohne diesen Schritt würde der Browser
  // beim Mousedown den Fokus aus der Textarea ziehen und das onblur-
  // Handler vor unserem save() laufen lassen.
  save(event) {
    event.preventDefault()
    this.inputTarget.onblur = null
    this.previewTarget.classList.remove("hidden")
    this.formTarget.classList.add("hidden")
    this.saveBtnTarget.classList.add("hidden")
    this.editBtnTarget.classList.remove("hidden")
    this.formTarget.requestSubmit()
  }
}
