import { Controller } from "@hotwired/stimulus"

// #87: drei Pop-Over-Menüs (Gruppieren / Sortieren / Filtern) im
// Listen-Header. Genau eines ist immer offen; Klick außerhalb schließt
// alle; ESC schließt alle.
//
// Persistenz: URL-Query ist Quelle der Wahrheit (vom Server gerendert);
// localStorage-Komfort merkt sich die letzten Settings je Entity-Liste
// und füttert sie beim ersten Index-Aufruf wieder zurück über eine
// einmalige Server-Redirect-Stufe (Controller-seitige Logik). Hier
// kümmern wir uns nur um Open/Close + Outside-Click.
export default class extends Controller {
  static targets = ["groupMenu", "sortMenu", "filterMenu"]

  connect() {
    this._onDocClick = (e) => {
      if (!this.element.contains(e.target)) this.closeAll()
    }
    this._onKey = (e) => { if (e.key === "Escape") this.closeAll() }
    document.addEventListener("click", this._onDocClick)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    document.removeEventListener("click", this._onDocClick)
    document.removeEventListener("keydown", this._onKey)
  }

  toggleGroup(event)  { this._toggle(event, "groupMenu") }
  toggleSort(event)   { this._toggle(event, "sortMenu") }
  toggleFilter(event) { this._toggle(event, "filterMenu") }

  _toggle(event, name) {
    event.stopPropagation()
    const target = this[`${name}Target`]
    const wasHidden = target.classList.contains("hidden")
    this.closeAll()
    if (wasHidden) {
      target.classList.remove("hidden")
      this._position(event.currentTarget, target)
    }
  }

  // Auf Mobile (< sm) hängen wir das Pop-Over fest am viewport, weil der
  // umgebende relative-Container nur die Icon-Breite hat — `absolute
  // right-0 w-80` würde sonst nach links aus dem Bildschirm ragen.
  _position(button, menu) {
    if (window.innerWidth < 640) {
      const rect = button.getBoundingClientRect()
      menu.style.position = "fixed"
      menu.style.top = `${rect.bottom + 4}px`
      menu.style.left = "0.5rem"
      menu.style.right = "0.5rem"
      menu.style.width = "auto"
      menu.style.maxWidth = "none"
    } else {
      menu.style.position = ""
      menu.style.top = ""
      menu.style.left = ""
      menu.style.right = ""
      menu.style.width = ""
      menu.style.maxWidth = ""
    }
  }

  closeAll() {
    for (const t of ["groupMenu", "sortMenu", "filterMenu"]) {
      if (this[`has${t.charAt(0).toUpperCase() + t.slice(1)}Target`]) {
        const menu = this[`${t}Target`]
        menu.classList.add("hidden")
        // Inline-Position-Styles abräumen, damit beim nächsten Open ein
        // sauberes Re-Layout entsteht (sonst klebt das Pop-Over an einer
        // alten Position, wenn der User zwischen Mobile und Desktop
        // wechselt oder rotiert).
        menu.style.position = ""
        menu.style.top = ""
        menu.style.left = ""
        menu.style.right = ""
        menu.style.width = ""
        menu.style.maxWidth = ""
      }
    }
  }
}
