import { Controller } from "@hotwired/stimulus"

// immoOS #1658 (Hans): Symbole in Hilfetexte einsetzen, ohne Namen zu kennen.
//
// Der Knopf öffnet ein Raster; ein Klick darin schreibt den Marker an die
// Cursorstelle des Schreibfeldes. Gesucht wird clientseitig — die Liste steht
// vollständig im Frame, es gibt nichts nachzuladen.
export default class extends Controller {
  static targets = ["suche", "eintrag", "raster", "textSuche", "textTreffer"]
  static values  = { bereich: String }

  // #1658 R15 (Hans): „… dann soll der Text für das Symbol beim Klicken auf das
  // Symbol in die Zwischenablage kopiert werden, damit ich ihn danach im Text
  // einfügen kann."
  //
  // Vorher schrieb der Klick den Marker direkt an die Cursorstelle des
  // Schreibfeldes — nur kam er dort nicht mehr an, seit der Editor CM6 ist: Die
  // Textarea ist versteckt, CM6 hält den Text, und was jemand in die Textarea
  // schreibt, überschreibt CM6 beim nächsten Tastendruck. Für Hans sah das aus
  // wie „der Klick tut nichts". Jetzt kopiert der Klick, und Einfügen macht der
  // Mensch an der Stelle, die er meint.
  async einsetzen(event) {
    event.preventDefault()
    const marker = event.currentTarget.dataset.marker
    if (!marker) return

    try {
      await navigator.clipboard.writeText(marker)
      this._melden(window.t("hilfe.icons.kopiert", { marker: marker }))
    } catch (err) {
      console.warn("clipboard copy failed:", err)
      this._melden(window.t("copy.copy_failed"))
    }
  }

  // Kurze Meldung im Toast-Stapel — dasselbe Muster wie copy-clipboard.
  _melden(text) {
    const stapel = document.getElementById("toast_stack")
    if (!stapel) return

    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    const span = document.createElement("span")
    span.className = "flex-1 min-w-0"
    span.textContent = text
    div.appendChild(span)
    stapel.appendChild(div)
  }

  filtern() {
    const suche = this.sucheTarget.value.trim().toLowerCase()
    this.eintragTargets.forEach((el) => {
      const treffer = !suche || (el.dataset.suchtext || "").includes(suche)
      el.classList.toggle("hidden", !treffer)
    })
  }

  // #1658 R6: Feld- und Abschnittsbezeichnungen suchen. Gesucht wird nach dem
  // Wort, das auf dem Bildschirm steht; zurück kommt der Übersetzungsschlüssel,
  // den der Hilfetext zitiert.
  async bezeichnungen() {
    const begriff = this.textSucheTarget.value.trim()
    if (begriff.length < 2) { this.textTrefferTarget.innerHTML = ""; return }

    // Die Karten-Art mitgeben: Treffer aus dem passenden Zusammenhang stehen
    // dann oben (#1658 R11 — ohne das griff der erste echte Gebrauch daneben).
    const bereich = this.hasBereichValue ? `&bereich=${encodeURIComponent(this.bereichValue)}` : ""
    const res = await fetch(`/help/bezeichnungen?q=${encodeURIComponent(begriff)}${bereich}`,
                            { headers: { Accept: "application/json" } })
    if (!res.ok) return
    const daten = await res.json()
    this.textTrefferTarget.innerHTML = (daten.treffer || []).map((t) => {
      const text = this._escape(t.text)
      const schluessel = this._escape(t.schluessel)
      return `<div class="flex items-center gap-1">
        <button type="button" data-action="click->icon-picker#einsetzen"
                data-marker=":feld:${schluessel}:" title=":feld:${schluessel}:"
                class="px-1.5 py-0.5 rounded border border-slate-200 bg-white hover:bg-indigo-50
                       hover:border-indigo-300 cursor-pointer text-[11px] font-semibold">${text}</button>
        <button type="button" data-action="click->icon-picker#einsetzen"
                data-marker=":bereich:${schluessel}:" title=":bereich:${schluessel}:"
                class="px-1 py-0.5 rounded border border-transparent hover:bg-slate-100
                       cursor-pointer text-[10px] text-slate-500">${this._escape(window.t("icon_picker.als_bereich"))}</button>
        <span class="text-[10px] text-slate-400 truncate">${schluessel}</span>
      </div>`
    }).join("")
  }

  _escape(s) {
    return String(s).replace(/[&<>"']/g, (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])
  }

  // Das Schreibfeld dieses Bereichs — der Picker sitzt darin.
  _feld() {
    return this.element.closest("[data-inline-edit-target='form'], form")?.querySelector("textarea")
  }
}
