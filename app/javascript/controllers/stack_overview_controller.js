import { Controller } from "@hotwired/stimulus"

// #1453 (aus immoos #1452 übernommen). Hans: „Um sich innerhalb des Stack zu
// orientieren, gibt es mobil im Moment nur oben links und rechts in der Ecke
// die Anzahl der Cards …
// Um zu sehen, welche Cards das sind, muss man allerdings durchswipen.
//
// Neu: Bei Tap auf die Zahlen öffnet sich eine Ansicht mit allen Spines, der
// aktuelle Spine ist hervorgehoben. Durch Tap auf einen Spine wird dieser
// geöffnet."
//
// Die Liste wird beim Öffnen aus dem DOM gelesen, nicht mitgeführt: Der Stapel
// ändert sich bei jedem Klick, und eine zweite Buchführung darüber wäre eine
// Quelle für Abweichungen. Was auf dem Schirm steht, ist die Wahrheit.
export default class extends Controller {
  static targets = ["blatt", "liste"]

  connect() {
    this.container = document.getElementById("blade_stack_container")
    this._onKey = (e) => { if (e.key === "Escape") this.schliessen() }
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
  }

  oeffnen(event) {
    event?.preventDefault()
    if (!this.container || !this.hasBlattTarget) return

    this.fuellen()
    this.blattTarget.classList.remove("hidden")
    document.addEventListener("keydown", this._onKey)
  }

  schliessen() {
    this.blattTarget?.classList.add("hidden")
    document.removeEventListener("keydown", this._onKey)
  }

  // Ein Tap auf die Fläche neben der Liste schließt — wie bei einem Popover.
  hintergrund(event) {
    if (event.target === this.blattTarget) this.schliessen()
  }

  fuellen() {
    const karten = Array.from(this.container.querySelectorAll("article.stack-card"))
    const aktiv = this.aktiveKarte(karten)
    this.listeTarget.replaceChildren(...karten.map((karte, i) => this.zeile(karte, i, karte === aktiv)))
  }

  // Welche Card gerade sichtbar ist, sagt im Mobile-Layout die Scrollposition
  // (jede Card ist bildschirmbreit, scroll-snap). Auf dem Schreibtisch trägt
  // die aktive Card data-active="true".
  aktiveKarte(karten) {
    const markiert = karten.find(k => k.dataset.active === "true")
    if (markiert) return markiert

    const breite = karten[0]?.getBoundingClientRect().width || 0
    if (breite <= 0) return karten[0]

    return karten[Math.min(karten.length - 1, Math.round(this.container.scrollLeft / breite))]
  }

  zeile(karte, index, istAktiv) {
    const spine = karte.querySelector(".stack-spine")
    const knopf = document.createElement("button")
    knopf.type = "button"
    knopf.className = [
      "w-full text-left px-2 py-2 flex items-center gap-2 border-b border-slate-100",
      istAktiv ? "bg-sky-50 text-sky-800 font-medium" : "text-slate-700 hover:bg-slate-50"
    ].join(" ")

    // R2 (Hans): „Bitte auch die Entitätsicons und die Spine-Farben
    // anzeigen." — Beides steht am Kartenrücken; übernommen wird, was dort
    // TATSÄCHLICH gerendert ist, statt es hier ein zweites Mal zu bestimmen.
    // Die Farbe kommt aus dem berechneten Stil und trägt damit auch den
    // Fokus-Zustand mit (aktive Card = kräftiger), genau wie im Stapel.
    const balken = document.createElement("span")
    balken.className = "shrink-0 w-1.5 self-stretch rounded-sm"
    if (spine) balken.style.backgroundColor = getComputedStyle(spine).backgroundColor

    const nummer = document.createElement("span")
    nummer.className = "shrink-0 w-4 text-[11px] tabular-nums text-slate-400"
    nummer.textContent = String(index + 1)

    const zeichen = document.createElement("span")
    zeichen.className = "shrink-0 text-slate-500 [&_svg]:w-4 [&_svg]:h-4"
    // Das Entitäts-Zeichen ist das erste SVG im Spine (blade_spine: icon_html
    // steht vor Kopier-Knopf, Verlauf und Schließen).
    const svg = spine?.querySelector(":scope > span:first-of-type svg")
    if (svg) zeichen.append(svg.cloneNode(true))

    const titel = document.createElement("span")
    titel.className = "truncate min-w-0 flex-1 text-[13px]"
    titel.textContent = this.beschriftung(karte)

    knopf.append(balken, nummer, zeichen, titel)
    if (istAktiv) {
      const hier = document.createElement("span")
      hier.className = "shrink-0 text-[10px] uppercase tracking-wide text-sky-700"
      hier.textContent = this.element.dataset.stackOverviewHierValue || "hier"
      knopf.append(hier)
    }

    knopf.addEventListener("click", () => {
      this.schliessen()
      karte.scrollIntoView({ behavior: "smooth", inline: "start", block: "nearest" })
    })
    return knopf
  }

  // Die Beschriftung steht am Kartenrücken (blade_spine: title/aria-label) —
  // dieselbe, die man beim Durchswipen sieht.
  beschriftung(karte) {
    const spine = karte.querySelector(".stack-spine")
    return (spine?.getAttribute("title") || spine?.textContent || karte.dataset.uuid || "").trim()
  }
}
