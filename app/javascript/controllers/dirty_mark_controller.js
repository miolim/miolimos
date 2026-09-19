import { Controller } from "@hotwired/stimulus"

// immoOS #1658 R10 (Hans): „Ich kann andere Karten aufrufen, ohne die
// Bearbeitung zu beenden."
//
// `dirty-warn` kann das nicht leisten: Es hängt zusätzlich an jedem
// Navigations-Versuch und fragt dann „Es gibt ungespeicherte Änderungen.
// Trotzdem fortfahren?" — im Stapel ist aber schon das Öffnen einer anderen
// Karte ein Navigations-Versuch (gemessen am 18.09.). Der Dialog käme also bei
// genau dem, was erlaubt sein soll.
//
// Gebraucht wird nur die MARKIERUNG: Der blade-stack sucht beim Schließen einer
// Card nach `[data-dirty="true"]` und fragt dann nach. Genau das — und sonst
// nichts — macht dieser Controller.
export default class extends Controller {
  mark() {
    this.element.dataset.dirty = "true"
  }

  clear() {
    delete this.element.dataset.dirty
  }
}
