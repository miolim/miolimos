import { Controller } from "@hotwired/stimulus"

// #705 (Hans, 2026-06-15): HTML-Artefakt-Blade. Der KI-Body wird als
// sandboxed iframe gerendert (allow-scripts, NICHT allow-same-origin → das
// HTML läuft isoliert, kommt nicht an die App/Session). Dieses Controller-
// Stück passt nur die iframe-Höhe an: das injizierte Resize-Skript im
// iframe postet seine Inhaltshöhe, wir setzen sie als Höhe. Quelle wird
// streng geprüft (nur unser eigenes iframe, korrekter Marker).
export default class extends Controller {
  static targets = ["frame"]

  connect() {
    this._onMsg = (e) => {
      if (!e.data || e.data.__htmlArtifact !== true) return
      if (!this.hasFrameTarget || e.source !== this.frameTarget.contentWindow) return
      const h = Math.min(20000, Math.max(80, Number(e.data.height) || 0))
      // #705 R2 (Hans): nur bei echter Änderung setzen — verhindert
      // Mikro-Oszillation/Aufschaukeln.
      if (Math.abs(h - (this._lastH || 0)) < 2) return
      this._lastH = h
      this.frameTarget.style.height = `${h + 2}px`
    }
    window.addEventListener("message", this._onMsg)
  }

  disconnect() {
    window.removeEventListener("message", this._onMsg)
  }
}
