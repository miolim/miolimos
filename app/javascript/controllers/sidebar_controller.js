import { Controller } from "@hotwired/stimulus"

// Desktop-Collapse für die Hauptnavigation. Schaltet zwischen Voll-
// (w-60, Icon + Label) und Schmal-Modus (w-14, nur Icons) per
// data-collapsed-Attribut. Tailwind data-Variants und group-data-
// Selektoren übernehmen das Styling auf den Kindern.
//
// Persistent-State liegt in localStorage. Zusätzlich (#154): beim
// Hover über die Sidebar wird sie temporär ausgeklappt, ohne die
// persistente Einstellung zu ändern. Mouseleave und Klick auf einen
// Nav-Link klappen sie wieder ein. Toggle-Button bleibt master für
// den persistenten Zustand.
//
// Auf Mobile irrelevant — dort regelt mobile_nav_controller das
// Slide-In/Out komplett separat.
export default class extends Controller {
  static values = { storageKey: { type: String, default: "sidebar.collapsed" } }

  connect() {
    const saved = localStorage.getItem(this.storageKeyValue)
    if (saved === null) {
      // Kein User-Wunsch gespeichert: bei < lg (1024px) default
      // einklappen — Stack-Bereich profitiert vom Platz mehr als
      // die Labels in der Nav. Mobile (< md) ist eh Hamburger,
      // dort ist `data-collapsed` nicht sichtbar.
      this.persistentCollapsed = window.matchMedia("(max-width: 1023px)").matches
    } else {
      this.persistentCollapsed = saved === "true"
    }
    this.hoverActive = false
    // #268: Cookie syncen, damit der naechste Server-Render die
    // Sidebar direkt im richtigen Modus zeichnet (kein Flackern).
    this._writeCookie()
    this.applyEffective()

    // #194: Scrollposition der Sidebar über Navigationen erhalten.
    // Wird in sessionStorage gespeichert (nicht localStorage, weil
    // sessionspezifisch sinnvoller ist — andere Browser-Tabs sollen
    // eigene Position halten).
    this.scrollKey = "sidebar.scrollTop"
    this.restoreScrollSoon()
    this.scrollHandler = this.saveScroll.bind(this)
    this.element.addEventListener("scroll", this.scrollHandler, { passive: true })
  }

  disconnect() {
    if (this.scrollHandler) {
      this.element.removeEventListener("scroll", this.scrollHandler)
    }
  }

  saveScroll() {
    sessionStorage.setItem(this.scrollKey, String(this.element.scrollTop))
  }

  restoreScrollSoon() {
    const saved = sessionStorage.getItem(this.scrollKey)
    if (saved === null) return
    const top = parseInt(saved, 10)
    if (!Number.isFinite(top) || top <= 0) return
    // Direkt setzen + nach Layout-Tick nochmal, weil Turbo nach
    // Stimulus-connect manchmal noch Render-Schritte macht, die den
    // Scroll resetten.
    this.element.scrollTop = top
    requestAnimationFrame(() => { this.element.scrollTop = top })
  }

  toggle() {
    this.persistentCollapsed = !this.persistentCollapsed
    this.hoverActive = false
    localStorage.setItem(this.storageKeyValue, String(this.persistentCollapsed))
    this._writeCookie()
    this.applyEffective()
  }

  // #268: Cookie spiegelt persistentCollapsed serverseitig — der naechste
  // Render zeichnet die Sidebar direkt im richtigen Modus, ohne den
  // expand→collapse-Sprung beim Reload.
  _writeCookie() {
    document.cookie =
      `sidebar_collapsed=${this.persistentCollapsed}; path=/; max-age=31536000; samesite=lax`
  }

  // mouseenter auf der Sidebar. Wirkt nur, wenn die Sidebar persistent
  // collapsed ist — sonst kein State-Change nötig.
  hoverExpand() {
    if (this.persistentCollapsed && !this.hoverActive) {
      this.hoverActive = true
      this.applyEffective()
    }
  }

  // mouseleave ODER Click auf einen Nav-Link. Klappt die hover-bedingt
  // ausgefahrene Sidebar wieder ein. Lässt den Persistent-State
  // unangetastet.
  hoverCollapse() {
    if (this.hoverActive) {
      this.hoverActive = false
      this.applyEffective()
    }
  }

  applyEffective() {
    // #250 v2: zwei separate State-Attribute.
    //   data-collapsed             → effective (persistent && !hover); steuert die internen
    //                                CSS-Group-Variants, die Labels ein-/ausblenden. Bleibt mit
    //                                der bisherigen Semantik kompatibel.
    //   data-persistent-collapsed  → reine Persistenz; steuert md:fixed / Position. Bei
    //                                persistent-collapsed lebt die Aside dauerhaft als Overlay,
    //                                der Placeholder haelt den Flow-Slot — Hover aendert nur
    //                                die Aside-Breite, kein Flow-Wechsel.
    const effectiveCollapsed = this.persistentCollapsed && !this.hoverActive
    this.element.dataset.collapsed            = effectiveCollapsed       ? "true" : "false"
    this.element.dataset.persistentCollapsed  = this.persistentCollapsed ? "true" : "false"
    this.element.dataset.hoverActive          = this.hoverActive         ? "true" : "false"
    const placeholder = this.element.nextElementSibling
    if (placeholder && "sidebarPlaceholder" in placeholder.dataset) {
      placeholder.dataset.active = this.persistentCollapsed ? "true" : "false"
    }
  }
}
