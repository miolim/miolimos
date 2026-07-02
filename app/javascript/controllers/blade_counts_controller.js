import { Controller } from "@hotwired/stimulus"

// #262: Auf Mobile zeigt die Topbar an, wieviele Blades vor und hinter
// der aktuell sichtbaren Card liegen. Links vom Hamburger-Menue der
// Count nach links, rechts neben „Abmelden" der nach rechts.
// Reagiert auf Scroll (scroll-snap zwischen Cards) und auf
// DOM-Mutationen (Cards hinzu/entfernt). Auf Desktop unsichtbar.
export default class extends Controller {
  static targets = ["left", "right"]

  connect() {
    this.container = document.getElementById("blade_stack_container")
    this._media    = window.matchMedia("(max-width: 767px)")
    this._onScroll = () => this.update()
    this._onMedia  = () => this.update()
    if (this.container) {
      this.container.addEventListener("scroll", this._onScroll, { passive: true })
      this._mo = new MutationObserver(() => this.update())
      this._mo.observe(this.container, { childList: true })
    }
    this._media.addEventListener("change", this._onMedia)
    this.update()
  }

  disconnect() {
    if (this.container && this._onScroll) {
      this.container.removeEventListener("scroll", this._onScroll)
    }
    this._mo?.disconnect()
    this._media?.removeEventListener("change", this._onMedia)
  }

  update() {
    // Auf Desktop oder ohne Stack-Container: beides verstecken.
    if (!this.container || !this._media.matches) { this._set(0, 0); return }
    const cards = this.container.querySelectorAll(".stack-card")
    if (cards.length <= 1) { this._set(0, 0); return }
    // Mobile-Layout: jede Card ist 100vw, scroll-snap mandatory.
    // Sichtbarer Index = scrollLeft / cardWidth (gerundet).
    const w = cards[0].getBoundingClientRect().width
    if (w <= 0) { this._set(0, 0); return }
    const idx   = Math.round(this.container.scrollLeft / w)
    const left  = Math.max(0, idx)
    const right = Math.max(0, cards.length - idx - 1)
    this._set(left, right)
  }

  _set(left, right) {
    // #262 follow-up: Anzeigeplatz immer reservieren — keine Pfeile,
    // nur die fette Zahl. Bei 0 verbleibt das Element im Flow, nur
    // sichtbar abgedimmt (opacity-30). Desktop blendet via md:hidden
    // im Markup beides komplett aus.
    if (this.hasLeftTarget) {
      this.leftTarget.textContent = String(left)
      this.leftTarget.classList.toggle("opacity-30", left === 0)
    }
    if (this.hasRightTarget) {
      this.rightTarget.textContent = String(right)
      this.rightTarget.classList.toggle("opacity-30", right === 0)
    }
  }
}
