// #378 Phase 8 (Hans, 2026-05-26): Spine-Marker-Logic aus
// blade_stack_controller.js ausgelagert. Reine DOM-Decoration auf
// Basis des Stack-Models (this.containerTarget). Wird als Mixin auf
// das Controller-Prototype angewendet, damit `this` weiterhin den
// Stack-Controller meint (Targets, setActiveCard, scrollCardIntoView,
// _scrollCardIntoFocus, _isDesktop). Reines Code-Move, kein Verhalten.
//
// Enthaltene Methoden:
//   _refreshInstanceCounters    — N/M-Badge bei mehrfach gestapelten UUIDs
//   _instanceGroupKey           — Topic-Tab-Suffix-Normalisierung
//   _rotateInstance             — Klick auf Counter-Badge -> naechste Instanz
//   _upgradeSpineTopIcons       — Spine-Top-Icon -> Hover-Close-X
//
// #1067 (Hans, 2026-07-20): _refreshInStackMarkers samt Jump-Chevron,
// Bold-Klasse und den Helfern _stackIdFromElement/_stackIdFromKindId ist
// entfernt. Offene Eintraege werden nur noch rot markiert
// (stack_highlight_controller.js) — der Chevron schob die Zeile ausserdem
// sichtbar ein, was neben der Farbe als zweite Sprache gelesen wurde.

// #1412 (Hans): Wo im Spine der Instanz-Zaehler sitzt — an ZWEITER Stelle,
// unter dem Card-Icon. Als eigene Funktion, damit die Regel ohne DOM
// pruefbar ist: Aus der Liste der Spine-Kinder (jeweils: steckt ein <svg>
// darin?) faellt der Index, HINTER den der Zaehler gehoert.
//
// Anker ist das ICON, nicht die feste Position — manche Spines tragen davor
// noch einen Themenfarb-Punkt (ein span ohne svg). Gibt es gar kein Icon,
// kommt der Zaehler nach vorn (-1 = ganz an den Anfang).
export function counterAnchorIndex(hasSvgFlags) {
  const idx = hasSvgFlags.findIndex(Boolean)
  return idx
}

export const BladeStackSpineMixin = {
  // #320 (Hans, 2026-05-24): Counter-Badge auf jedem Spine, dessen
  // data-uuid mehr als einmal im Stack vorkommt. Listen-Blades sind
  // explizit MIT enthalten (Hans-Spec follow-up). Wir gruppieren alle
  // .stack-card[data-uuid] nach UUID und setzen pro Card im Spine ein
  // <span class="stack-instance-counter">N</span> direkt am Anfang.
  _refreshInstanceCounters() {
    const cards = Array.from(this.containerTarget.querySelectorAll(".stack-card[data-uuid]"))
    const byKey = new Map()
    cards.forEach(c => {
      const uuid = c.dataset.uuid
      if (!uuid) return
      const key = this._instanceGroupKey(uuid)
      if (!byKey.has(key)) byKey.set(key, [])
      byKey.get(key).push(c)
    })
    cards.forEach(card => {
      const spine = card.querySelector(".stack-spine")
      if (!spine) return
      const group = byKey.get(this._instanceGroupKey(card.dataset.uuid)) || []
      const existing = spine.querySelector(".stack-instance-counter")
      if (group.length < 2) {
        if (existing) existing.remove()
        return
      }
      const idxInGroup = group.indexOf(card) + 1
      const label = `${idxInGroup}/${group.length}`
      if (existing) {
        existing.textContent = label
      } else {
        const badge = document.createElement("button")
        badge.type = "button"
        badge.className = "stack-instance-counter"
        badge.textContent = label
        badge.title = window.t("blade_stack.multi_instance_title", { count: group.length })
        // Klick rotiert zur naechsten Instanz (Hans-Spec #320).
        // stopPropagation, damit der Spine-Click-Handler nicht zusaetzlich
        // diese Card fokussiert.
        badge.addEventListener("click", (e) => {
          e.preventDefault()
          e.stopPropagation()
          this._rotateInstance(card)
        })
        // #1412 (Hans): Der Zaehler sitzt an ZWEITER Stelle, unter dem
        // Card-Icon — nicht ganz oben. Vorher schob er das Icon und alles
        // darunter nach unten; das Icon ist aber das, woran man die Card
        // erkennt, und es soll dort bleiben, wo es immer sitzt.
        //
        // Anker ist das Icon, nicht die Position: Manche Spines tragen davor
        // noch einen Themenfarb-Punkt (`pre_icon`, ein span OHNE svg). Das
        // Icon ist das erste Kind, in dem ein <svg> steckt.
        const kinder = Array.from(spine.children)
        const idx = counterAnchorIndex(kinder.map(el => !!el.querySelector?.("svg")))
        if (idx >= 0) {
          kinder[idx].insertAdjacentElement("afterend", badge)
        } else {
          spine.insertBefore(badge, spine.firstChild)
        }
      }
    })
  },

  // #354 (Hans, 2026-05-25): Gruppen-Key fuer Instance-Counter.
  // `list:topic:slug:tab` und `list:topic:slug` zaehlen als dieselbe
  // Topic-Instanz (Tabs sind unterschiedliche Views derselben Sache).
  // Alle anderen UUIDs sind ihr eigener Key.
  _instanceGroupKey(uuid) {
    if (!uuid) return ""
    if (uuid.startsWith("list:topic:")) {
      const rest = uuid.slice(11)
      const sepIdx = rest.indexOf(":")
      // Tab-Suffix abschneiden, falls vorhanden.
      const slug = sepIdx > 0 ? rest.slice(0, sepIdx) : rest
      return `list:topic:${slug}`
    }
    return uuid
  },

  // #320 (Hans): Klick auf das Counter-Badge → naechste Instanz des
  // gleichen UUID in den Focus scrollen.
  // #354 (Hans, 2026-05-25): Gruppierung ueber _instanceGroupKey statt
  // exact-uuid-match, damit `list:topic:slug` und `list:topic:slug:tab`
  // weiterhin als gleiche Topic-Instanz gelten (Tab-Suffix gilt nicht
  // als Identitaetswechsel).
  _rotateInstance(fromCard) {
    const uuid = fromCard.dataset.uuid
    if (!uuid) return
    const key = this._instanceGroupKey(uuid)
    const all = Array.from(this.containerTarget.querySelectorAll(".stack-card[data-uuid]"))
      .filter(c => this._instanceGroupKey(c.dataset.uuid) === key)
    if (all.length < 2) return
    const here = all.indexOf(fromCard)
    const next = all[(here + 1) % all.length]
    if (!next) return
    this.setActiveCard(next)
    this._scrollCardIntoFocus(next)
  },

  // #289: Spine-Top-Icon wird per JS auf jedem Spine in einen Hover-
  // Close-Button verwandelt — Original-Icon bleibt, daneben sitzt ein
  // X-Overlay, das per CSS bei :hover sichtbar wird; Click closeCard().
  // Zentral via JS statt 20 Partial-Edits.
  _upgradeSpineTopIcons() {
    if (!this._isDesktop()) return
    const X_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="w-5 h-5"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>`
    this.containerTarget.querySelectorAll(".stack-spine").forEach(spine => {
      if (spine.dataset.topUpgraded) return
      const first = spine.querySelector(":scope > span:first-child")
      if (!first) return
      spine.dataset.topUpgraded = "1"
      const wrapper = document.createElement("button")
      wrapper.type = "button"
      wrapper.className = "spine-top-close group/spine-top relative shrink-0 p-0 bg-transparent border-0 cursor-pointer"
      wrapper.title = window.t("blade_stack.close_card")
      wrapper.setAttribute("aria-label", "Schliessen")
      wrapper.setAttribute("data-action", "click->blade-stack#closeCard")
      first.parentNode.insertBefore(wrapper, first)
      wrapper.appendChild(first)
      first.classList.add("transition-opacity", "block", "group-hover/spine-top:opacity-0")
      // #289 v2: heller Hintergrund + dunkles X (Hans: gleiche Optik wie
      // das X unten — kein rotes Kreuz, sondern bg-slate-100 + slate-700).
      const x = document.createElement("span")
      x.className = "absolute inset-0 flex items-center justify-center rounded bg-slate-100 text-slate-700 opacity-0 transition-opacity group-hover/spine-top:opacity-100"
      x.innerHTML = X_SVG
      wrapper.appendChild(x)
    })
  }
}
