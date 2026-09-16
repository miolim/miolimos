// #1642 (Hans, 2026-09-16): „Wenn man die UMSCHALT-Taste beim Klick gedrückt
// hält, erscheint ein Kontextmenü: Karte links öffnen / Karte rechts öffnen /
// Karte am Ende öffnen. Damit muss man sich nicht die unterschiedlichen
// Modifier merken, sondern nur einen." — Hans wählte Variante B: NUR noch das
// Menü; die Alt-Kombinationen aus #1509 entfallen. Dazu sein Zusatz: „‚hier
// ersetzen' ist eigentlich ‚rechts ersetzen'; ja, das kann auch mit
// aufgenommen werden."
//
// Die Regel gilt an allen drei Klickwegen (blade_link_controller#append,
// blade_stack_openers#openFromList und #openDocument) — sie fragen alle
// `oeffnungsart(event)`:
//
//   Klick            ersetzt alles rechts der aufrufenden Karte
//   Umschalt+Klick   Menü: rechts ersetzen · links · rechts · ans Ende
//   Cmd/Strg         gehört dem Browser („in neuem Tab öffnen")
//
// Das Menü ist bewusst dasselbe Muster wie das Schließen-Menü am Kartenrücken
// (#1032): ein kleines Div am Klickpunkt, Escape und Klick daneben schließen.

export const OEFFNUNGSARTEN = ["ersetzen", "links", "rechts", "ende"]

// Was der Klick OHNE Menü bedeutet. Sprachneutral und ohne DOM — der
// JS-Test prüft genau diese Funktion.
export function grundart(event) {
  if (event?.metaKey || event?.ctrlKey) return "browser"
  if (event?.shiftKey) return "menue"
  return "ersetzen"
}

// Liefert die gewählte Öffnungsart: "ersetzen" | "links" | "rechts" | "ende",
// "browser" (der Klick gehört dem Browser) oder null (Menü abgebrochen).
export async function oeffnungsart(event) {
  const art = grundart(event)
  if (art !== "menue") return art
  return zeigeOeffnenMenue(event)
}

// Menü am Klickpunkt. Auflösung erst, wenn gewählt oder abgebrochen wurde.
export function zeigeOeffnenMenue(event) {
  return new Promise((resolve) => {
    document.getElementById("blade_open_menu")?.remove()

    const menu = document.createElement("div")
    menu.id = "blade_open_menu"
    menu.className = "fixed z-50 bg-white border border-slate-200 rounded shadow-lg py-1 min-w-52 text-sm text-slate-700"

    let fertig = false
    const schliessen = (wahl) => {
      if (fertig) return
      fertig = true
      menu.remove()
      document.removeEventListener("click", aufDaneben, true)
      document.removeEventListener("keydown", aufTaste, true)
      window.removeEventListener("scroll", aufDaneben, true)
      window.removeEventListener("resize", aufDaneben)
      resolve(wahl)
    }
    const aufDaneben = (e) => { if (!menu.contains(e.target)) schliessen(null) }
    const aufTaste   = (e) => { if (e.key === "Escape") { e.preventDefault(); schliessen(null) } }

    OEFFNUNGSARTEN.forEach((art) => {
      const b = document.createElement("button")
      b.type = "button"
      b.dataset.openArt = art
      b.className = "w-full text-left block px-3 py-1.5 bg-transparent border-0 cursor-pointer hover:bg-slate-50"
      b.textContent = window.t(`blade_open_menu.${art}`)
      b.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        schliessen(art)
      })
      menu.appendChild(b)
    })

    document.body.appendChild(menu)

    // Am Mauszeiger, in den sichtbaren Bereich geklemmt. Ohne Koordinaten
    // (Tastatur-Klick) unter dem angeklickten Element.
    const rect = event?.currentTarget?.getBoundingClientRect?.()
    const x = event?.clientX || rect?.left || 8
    const y = event?.clientY || rect?.bottom || 8
    const left = Math.max(8, Math.min(x, window.innerWidth  - menu.offsetWidth  - 8))
    let   top  = y + 4
    if (top + menu.offsetHeight > window.innerHeight - 8) top = Math.max(8, y - menu.offsetHeight - 4)
    menu.style.left = `${Math.round(left)}px`
    menu.style.top  = `${Math.round(top)}px`

    // Capture, damit ein Klick daneben nicht erst andere Handler auslöst.
    document.addEventListener("click", aufDaneben, true)
    document.addEventListener("keydown", aufTaste, true)
    window.addEventListener("scroll", aufDaneben, true)
    window.addEventListener("resize", aufDaneben)
  })
}
