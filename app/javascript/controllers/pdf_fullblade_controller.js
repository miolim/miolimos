import { Controller } from "@hotwired/stimulus"

// #683 (Hans, 2026-06-13): „PDF im ganzen Blade anzeigen". Legt den
// PDF-Reader als Overlay NUR über den Inhalts-Teil der Stack-Card
// (left-7 lässt den Spine frei — er bleibt als Navigation sichtbar) und
// blendet damit das übrige Blade-Interface (Titel, Toolbar, Sektionen)
// aus. Das Spine-Icon wechselt dabei auf das Reduce-Icon; erneuter Klick
// (bzw. Reduce) kehrt zur normalen Ansicht zurück. Neuer-Tab bleibt ein
// eigenes Spine-Icon daneben.
export default class extends Controller {
  static values  = { url: String }
  static targets = ["expandIcon", "reduceIcon"]

  toggle(event) {
    event.preventDefault()
    const card = this.element.closest(".stack-card")
    if (!card) return

    const existing = card.querySelector(":scope > .pdf-fullblade-overlay")
    if (existing) { existing.remove(); this.setActive(false); return }

    const overlay = document.createElement("div")
    // top/right/bottom-0 + left-7 (= Spine-Breite w-7): deckt nur den
    // Inhalts-Teil, der Spine bleibt sichtbar und bedienbar.
    overlay.className = "pdf-fullblade-overlay absolute top-0 right-0 bottom-0 left-7 z-30 bg-white"

    const frame = document.createElement("iframe")
    frame.src = `${this.urlValue}#view=FitH`
    frame.className = "w-full h-full border-0 bg-slate-50"

    overlay.appendChild(frame)
    card.appendChild(overlay)
    this.setActive(true)
  }

  setActive(active) {
    if (this.hasExpandIconTarget) this.expandIconTarget.classList.toggle("hidden", active)
    if (this.hasReduceIconTarget) this.reduceIconTarget.classList.toggle("hidden", !active)
    this.element.title = active ? "Zurück zur normalen Ansicht" : "PDF in der ganzen Card anzeigen"
    this.element.setAttribute("aria-label", this.element.title)
  }
}
