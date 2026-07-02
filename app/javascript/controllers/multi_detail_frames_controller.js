import { Controller } from "@hotwired/stimulus"

// Für Dashboard-ähnliche Right-Panes, die mehrere Turbo-Frames stacken
// (task_detail, awaiting_detail, communication_detail). Hört auf
// turbo:frame-load und:
//   - blendet einen optionalen Placeholder aus
//   - leert die anderen Frames, damit nur der zuletzt geladene sichtbar ist.
export default class extends Controller {
  static targets = ["placeholder"]

  connect() {
    this._onLoad = this.onLoad.bind(this)
    this.element.addEventListener("turbo:frame-load", this._onLoad)
    // #211 follow-up: Klicks auf Links wie /dashboard?task=12#task_comment_345
    // bekommen vom Browser KEINEN Anchor-Scroll, weil das Ziel-Element
    // erst nach dem Turbo-Frame-Swap im DOM existiert UND Turbo den
    // Hash aus dem advance-URL strippt. Wir fangen den Hash am Klick
    // ab und triggern eine Retry-Schleife (deckt auch den Fall ab, wo
    // die Task schon im Frame angezeigt wird und KEIN frame-load feuert).
    this._onCaptureClick = this._captureClickHash.bind(this)
    document.addEventListener("click", this._onCaptureClick, true)
    // #214-Follow: bei F5 auf /dashboard?task=X#task_comment_Y ist der
    // Frame schon serverseitig gerendert, kein turbo:frame-load fires.
    // Trotzdem zum Anchor scrollen.
    if (window.location.hash) this._wantScrollTo(window.location.hash)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this._onLoad)
    document.removeEventListener("click", this._onCaptureClick, true)
  }

  _captureClickHash(event) {
    const link = event.target.closest("a[href]")
    if (!link) return
    const frameName = link.getAttribute("data-turbo-frame")
    if (!frameName) return
    // Nur Frames in DIESEM Container interessieren uns.
    if (!this.element.querySelector(`turbo-frame#${CSS.escape(frameName)}`)) return
    let hash = ""
    try { hash = new URL(link.href, window.location.origin).hash } catch { return }
    if (hash) this._wantScrollTo(hash)
  }

  onLoad(event) {
    const loaded = event.target
    // #192: Nur reagieren, wenn das geladene Frame ein DIREKTES Kind
    // dieses Containers ist. Ein nested frame (z.B.
    // `task_comment_body_<id>` beim Comment-Edit innerhalb von
    // `task_detail`) löst ebenfalls turbo:frame-load aus — `loaded`
    // ist dann das innere Frame, und keiner der Geschwister ist
    // `=== loaded`. Ohne diesen Guard würden ALLE Schwestern-Frames
    // (inkl. `task_detail` selbst) entleert und der Detail-Bereich
    // wäre visuell leer.
    if (loaded.parentElement !== this.element) return

    if (this.hasPlaceholderTarget) this.placeholderTarget.classList.add("hidden")
    Array.from(this.element.children).forEach((child) => {
      if (child.tagName === "TURBO-FRAME" && child !== loaded) {
        child.innerHTML = ""
      }
    })

    // Wenn der Frame frisch geladen wurde, gib der Retry-Schleife einen
    // frischen Versuch — der Hash steht entweder im _pendingHash (am
    // Klick eingefangen) oder, als Fallback, an window.location.hash
    // (z.B. nach Turbo-Visit auf /dashboard?task=X#anchor).
    const hash = this._pendingHash || window.location.hash
    if (hash) this._wantScrollTo(hash)
  }

  // Externer Einstieg: Hash setzen + Retry-Schleife starten. Idempotent
  // — mehrfache Aufrufe ueberschreiben den Hash und resetten den Counter.
  _wantScrollTo(hash) {
    if (!hash || hash.length <= 1) return
    this._pendingHash = hash
    this._scrollAttempts = 0
    this._tryScrollNow()
  }

  // Versucht zu scrollen. Wenn das Ziel-Element noch nicht da ist (Frame
  // noch beim Laden), nach 50ms erneut versuchen — bis zu 20x = 1s.
  // Sobald das Element da ist und Scroll laeuft, _pendingHash zurueck-
  // setzen, damit ein eventuell spaeter feuerndes frame-load nichts mehr
  // doppelt scrollt.
  _tryScrollNow() {
    if (!this._pendingHash) return
    let target
    try { target = this.element.querySelector(this._pendingHash) } catch {
      this._pendingHash = null
      return
    }
    if (target) {
      const hash = this._pendingHash
      this._pendingHash = null
      // #211 follow-up: wenn das Ziel ein eingeklappter Comment ist
      // (li[data-controller=disclosure]), erst ausklappen — sonst sieht
      // der User den Header und denkt, der Scroll sei daneben gegangen.
      this._expandIfCollapsed(target)
      // requestAnimationFrame: Layout nach Disclosure-Expand neu
      // berechnen lassen, sonst springt scrollIntoView auf die
      // Pre-Expand-Position.
      requestAnimationFrame(() =>
        target.scrollIntoView({ behavior: "smooth", block: "start" })
      )
      return
    }
    // 100 Versuche × 50 ms = 5 s. Reicht auch fuer Frame-Loads bei
    // langsamem Server. Nach Aufgabe bleibt _pendingHash gesetzt, damit
    // ein spaeter feuerndes onLoad noch reagieren kann (es ruft erneut
    // _wantScrollTo auf und setzt den Counter zurueck).
    if (++this._scrollAttempts < 100) {
      setTimeout(() => this._tryScrollNow(), 50)
    }
  }

  _expandIfCollapsed(target) {
    const app = this.application
    if (!app) return
    // Disclosure haengt entweder am Ziel selbst (Comments) oder an einem
    // Vorfahren (z.B. ein eingeklappter Abschnitt um den Comment herum).
    // Wir laufen vom Target nach oben durch's DOM und expanden ALLE
    // eingeklappten Disclosures auf dem Weg.
    let el = target
    while (el && el !== document.body) {
      if (el.dataset && "controller" in el.dataset &&
          el.dataset.controller.split(/\s+/).includes("disclosure")) {
        const ctrl = app.getControllerForElementAndIdentifier(el, "disclosure")
        ctrl?.expand?.()
      }
      el = el.parentElement
    }
  }
}
