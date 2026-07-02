// #378 Phase 8 (Hans, 2026-05-26): Spine-Marker-Logic aus
// blade_stack_controller.js ausgelagert. Reine DOM-Decoration auf
// Basis des Stack-Models (this.containerTarget). Wird als Mixin auf
// das Controller-Prototype angewendet, damit `this` weiterhin den
// Stack-Controller meint (Targets, setActiveCard, scrollCardIntoView,
// _scrollCardIntoFocus, _isDesktop). Reines Code-Move, kein Verhalten.
//
// Enthaltene Methoden:
//   _refreshInStackMarkers      — in-Stack-Klasse + Jump-Pfeil auf Listen-Rows
//   _refreshInstanceCounters    — N/M-Badge bei mehrfach gestapelten UUIDs
//   _instanceGroupKey           — Topic-Tab-Suffix-Normalisierung
//   _rotateInstance             — Klick auf Counter-Badge -> naechste Instanz
//   _stackIdFromElement         — Element-Dataset -> Stack-UUID
//   _stackIdFromKindId          — (kind, id) -> Stack-UUID
//   _buildInStackJumpButton     — Jump-Button-DOM
//   _upgradeSpineTopIcons       — Spine-Top-Icon -> Hover-Close-X

export const BladeStackSpineMixin = {
  // #287: Markiere Listen-Rows, die einem im Stack geoeffneten Blade
  // entsprechen — fett (via CSS-Klasse) + Jump-Pfeil-Button, der per
  // scrollCardIntoView zur geoeffneten Card scrollt.
  _refreshInStackMarkers() {
    const inStack = new Set()
    this.containerTarget.querySelectorAll(".stack-card[data-uuid]").forEach(c => {
      inStack.add(c.dataset.uuid)
    })
    // Pro Row maximal ein Marker — wir bevorzugen <a>-Anchor (Titel-Link)
    // als Einfuegepunkt; sonst das erste passende Element.
    const rows = new Map()
    // #295: nur Elemente INNERHALB von <li> akzeptieren — sonst matched
    // die data-target-uuid auf den Spines selbst, und das Jump-Chevron
    // landet IN der Spine (Hans-Report). Spines sind keine Rows.
    const candidates = this.containerTarget.querySelectorAll(
      "li [data-blade-link-kind-value][data-blade-link-id-value], li [data-target-uuid]"
    )
    candidates.forEach(el => {
      const uuid = this._stackIdFromElement(el)
      if (!uuid) return
      const row = el.closest("li") || el.parentElement
      if (!row) return
      const existing = rows.get(row)
      // Anchor-Praeferenz: <a> ueberschreibt <button>.
      if (!existing || (el.tagName === "A" && existing.anchor.tagName !== "A")) {
        rows.set(row, { uuid, anchor: el })
      }
    })
    rows.forEach(({ uuid, anchor }, row) => {
      const isOpen = inStack.has(uuid)
      row.classList.toggle("in-stack", isOpen)
      let jump = row.querySelector(".in-stack-jump")
      if (isOpen && !jump) {
        jump = this._buildInStackJumpButton(uuid)
        // #611 (Hans): Chevron GANZ an den Zeilenanfang — einheitlich in
        // allen Listen (vorher: links vom Titel, je nach Row-Aufbau an
        // unterschiedlicher x-Position). Host = die Flex-Zeile selbst
        // (manche <li> sind selbst flex, andere wrappen ein flex-<div>).
        const host = (getComputedStyle(row).display === "flex")
          ? row
          : (Array.from(row.children).find(ch =>
              ch.tagName === "DIV" && getComputedStyle(ch).display === "flex") || row)
        host.prepend(jump)
      } else if (!isOpen && jump) {
        jump.remove()
      }
    })
  },

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
        badge.title = `Dieses Item ist ${group.length}× im Stack — Klick: naechste Instanz`
        // Klick rotiert zur naechsten Instanz (Hans-Spec #320).
        // stopPropagation, damit der Spine-Click-Handler nicht zusaetzlich
        // diese Card fokussiert.
        badge.addEventListener("click", (e) => {
          e.preventDefault()
          e.stopPropagation()
          this._rotateInstance(card)
        })
        spine.insertBefore(badge, spine.firstChild)
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

  // #287 v2: kind+id → stack-data-uuid. Spiegelt die Mapping-Logik aus
  // dem blade-stack:append-Handler. data-target-uuid (z.B. KI-Listen)
  // ist bereits ein bare-uuid und braucht keine Konvertierung.
  _stackIdFromElement(el) {
    if (el.dataset.bladeLinkKindValue && el.dataset.bladeLinkIdValue) {
      return this._stackIdFromKindId(el.dataset.bladeLinkKindValue, el.dataset.bladeLinkIdValue)
    }
    if (el.dataset.targetUuid) return el.dataset.targetUuid
    return null
  },

  _stackIdFromKindId(kind, id) {
    switch (kind) {
      case "topic":         return `topic:${id}`
      case "topic_list":    return `list:topic:${id}`
      case "task":          return `task:${id}`
      case "source":        return `src:${id}`
      case "awaiting":      return `awaiting:${id}`
      case "communication": return `communication:${id}`
      case "list":          return `list:${id}`
      case "ki":            return id
      default:              return null
    }
  },

  _buildInStackJumpButton(targetUuid) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "in-stack-jump shrink-0 p-0.5 rounded text-emerald-600 hover:bg-emerald-50 bg-transparent border-0 cursor-pointer"
    btn.title = "Zum offenen Blade springen"
    btn.setAttribute("aria-label", "Zum offenen Blade")
    btn.dataset.targetUuid = targetUuid
    btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="w-4 h-4"><path d="M9 6l6 6-6 6"/></svg>`
    btn.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      const card = this.containerTarget.querySelector(`.stack-card[data-uuid="${CSS.escape(targetUuid)}"]`)
      if (card) {
        this.scrollCardIntoView(card)
        this.setActiveCard(card)
      }
    })
    return btn
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
      wrapper.title = "Card schliessen"
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
