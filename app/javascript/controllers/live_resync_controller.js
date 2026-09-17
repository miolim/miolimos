import { Controller } from "@hotwired/stimulus"
import { istWiederverbunden, zaehlertext, pauseWarLang } from "lib/live_resync"

// #1653 (Hans): Antworten erscheinen erst nach manuellem Neuladen.
//
// Ursache (auf Produktion nachgemessen): Live-Updates kommen an, SOLANGE die
// Verbindung steht. Nachrichten aus einer Unterbrechung holt ActionCable aber
// nicht nach — und Unterbrechungen sind Alltag: jeder Deploy startet Puma neu,
// dazu Ruhezustand des Rechners und Netzwechsel. Postet der Agent genau in
// diesem Fenster (Deploy, dann Kommentar), bleibt die offene Card stehen.
//
// Deshalb hier: Nach jeder WIEDERverbindung — und nach einer laengeren Pause
// im Hintergrund — laedt sich die Antwortenliste einmal selbst nach. Das ist
// derselbe schonende Weg wie beim Live-Update (#232): nur das Listen-Frame,
// nie die ganze Card. Ein angefangener Antwort-Entwurf steht ausserhalb des
// Frames und bleibt unberuehrt.
//
// Markup: die Listen-Frames tragen
//   data-live-resync-src="<Pfad zum Listen-Fragment>"
//   data-count-id="<id des Zaehlers>"  data-replies-count="<Anzahl>"
export default class extends Controller {
  connect() {
    this._verbunden = new WeakMap()
    this._seitVersteckt = null

    // turbo-cable-stream-source setzt/entfernt das `connected`-Attribut.
    this._beobachter = new MutationObserver((eintraege) => {
      for (const e of eintraege) {
        if (e.attributeName !== "connected") continue
        const el     = e.target
        const jetzt  = el.hasAttribute("connected")
        const vorher = this._verbunden.get(el)
        // „getrennt" nur vermerken, wenn zuvor eine Verbindung STAND —
        // sonst bliebe der unbekannte Anfangszustand als false haengen.
        if (jetzt || vorher === true) this._verbunden.set(el, jetzt)
        if (istWiederverbunden(vorher, jetzt)) this._planeNachladen()
      }
    })
    this._beobachter.observe(document.documentElement, {
      subtree: true, attributes: true, attributeFilter: ["connected"]
    })

    // Nur bereits VERBUNDENE Elemente vormerken. Ein unbekannter Zustand darf
    // nicht als „getrennt" gelten — sonst sieht der erste Verbindungsaufbau
    // (der beim Laden der Seite immer kommt) wie eine Wiederverbindung aus
    // und jede Card laedt ihre Liste sofort ein zweites Mal.
    document.querySelectorAll("turbo-cable-stream-source").forEach((el) => {
      if (el.hasAttribute("connected")) this._verbunden.set(el, true)
    })

    // Tab war lange im Hintergrund: Browser drosseln dort Timer und schliessen
    // Verbindungen — beim Zurueckkommen dasselbe Nachladen.
    this._onSichtbar = () => {
      if (document.hidden) { this._seitVersteckt = Date.now(); return }
      const pause = this._seitVersteckt ? Date.now() - this._seitVersteckt : 0
      this._seitVersteckt = null
      if (pauseWarLang(pause)) this._planeNachladen()
    }
    document.addEventListener("visibilitychange", this._onSichtbar)

    // Nach dem Nachladen den Zaehler mitziehen — er steht ausserhalb des
    // Frames (sticky Kopfzeile) und kommt daher nicht mit dem Fragment.
    this._onFrameLoad = (event) => this._zaehlerNachziehen(event.target)
    document.addEventListener("turbo:frame-load", this._onFrameLoad)
  }

  disconnect() {
    this._beobachter?.disconnect()
    document.removeEventListener("visibilitychange", this._onSichtbar)
    document.removeEventListener("turbo:frame-load", this._onFrameLoad)
    clearTimeout(this._timer)
  }

  // Mehrere Streams verbinden sich gleichzeitig wieder — einmal reicht.
  _planeNachladen() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.nachladen(), 300)
  }

  nachladen() {
    document.querySelectorAll("turbo-frame[data-live-resync-src]").forEach((frame) => {
      const src = frame.dataset.liveResyncSrc
      if (!src) return
      // Frame ohne src (inline gerendert): src setzen laedt es. Mit src:
      // reload() holt dasselbe Fragment erneut.
      if (frame.getAttribute("src")) frame.reload()
      else frame.setAttribute("src", src)
    })
  }

  // Die Anzahl steht IM Frame-Inhalt (nicht als Attribut am Frame): Beim
  // Nachladen tauscht Turbo nur den Inhalt aus, Attribute am Frame bleiben
  // stehen — und damit auch eine veraltete Zahl.
  _zaehlerNachziehen(frame) {
    if (!frame?.dataset?.countId) return
    const ziel = document.getElementById(frame.dataset.countId)
    const quelle = frame.querySelector("[data-replies-count]")
    if (ziel && quelle) ziel.textContent = zaehlertext(quelle.dataset.repliesCount)
  }
}
