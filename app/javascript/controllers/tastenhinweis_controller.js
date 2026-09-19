import { Controller } from "@hotwired/stimulus"

// #1670 (Übernahme aus immoOS #1667, Hans): Hält man STRG+ALT oder
// STRG+UMSCHALT, zeigt die Topbar an, was die Pfeiltasten gerade tun.
//
// Zwei Griffe, die man sich sonst merken müsste (lib/blade_stack_keyboard.js):
//   STRG/Cmd + ALT      + ←/→   Kartenfokus wechseln
//   STRG/Cmd + UMSCHALT + ←/→   die fokussierte Karte im Stapel verschieben
//
// Der Hinweis liegt ÜBER der Topbar, statt an ihre Stelle zu treten: Würden
// die Symbole weichen, sprängen Suchfeld und Zonen in der Breite — bei einer
// Taste, die man nur kurz hält, liest sich das wie ein Fehler.
//
// Die Farbe des Kartenrückens hängt am Wurzelelement (`data-tastenmodus`),
// nicht an der Karte: Die Karten liegen außerhalb dieses Controllers, und
// welche fokussiert ist, weiß das CSS über `[data-active]` ohnehin schon.
export default class extends Controller {
  static targets = ["hinweis", "text"]
  static values = { fokus: String, verschieben: String }

  connect() {
    this._aufTaste     = (e) => this._pruefe(e)
    this._aufVerlassen = () => this._setze(null)
    // Am window, nicht am Element: Die Tasten gelten überall auf der Seite,
    // auch wenn der Cursor in einer Karte steht.
    window.addEventListener("keydown", this._aufTaste)
    window.addEventListener("keyup", this._aufTaste)
    // Wer mit gedrückter Taste wegklickt, bekommt nie ein keyup — ohne das
    // hier bliebe der Hinweis stehen, bis man die Taste erneut antippt.
    window.addEventListener("blur", this._aufVerlassen)
    document.addEventListener("visibilitychange", this._aufVerlassen)
  }

  disconnect() {
    window.removeEventListener("keydown", this._aufTaste)
    window.removeEventListener("keyup", this._aufTaste)
    window.removeEventListener("blur", this._aufVerlassen)
    document.removeEventListener("visibilitychange", this._aufVerlassen)
    this._setze(null)
  }

  // Genau die zwei Kombinationen, die auch die Pfeiltasten auswerten: STRG/Cmd
  // mit ALT oder mit UMSCHALT, nie mit beiden — sonst verspräche der Hinweis
  // etwas, das keine Taste einlöst.
  _pruefe(event) {
    const mod = event.ctrlKey || event.metaKey
    if (!mod) return this._setze(null)
    if (event.altKey && !event.shiftKey) return this._setze("fokus")
    if (event.shiftKey && !event.altKey) return this._setze("verschieben")
    this._setze(null)
  }

  _setze(modus) {
    if (this._modus === modus) return
    this._modus = modus

    this.hinweisTarget.classList.toggle("hidden", !modus)
    if (modus) this.textTarget.textContent = modus === "fokus" ? this.fokusValue : this.verschiebenValue

    if (modus === "verschieben") document.documentElement.dataset.tastenmodus = "verschieben"
    else delete document.documentElement.dataset.tastenmodus
  }
}
