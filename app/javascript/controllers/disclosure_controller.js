import { Controller } from "@hotwired/stimulus"

// Klappt ein Detail-Element auf/zu und rotiert ein Icon mit. Optional
// merkt sich der Controller den Zustand in localStorage, wenn ein
// storage-key gesetzt ist (z.B. für die Dashboard-Sektionen).
//
// Markup-Konvention für expanded-by-default:
//   icon-Span hat schon rotate-90, content hat KEIN hidden.
// Für collapsed-by-default genau umgekehrt.
export default class extends Controller {
  static targets = ["content", "icon"]
  static values  = {
    storageKey:    String,
    // Wenn gesetzt UND noch kein localStorage-Eintrag: bei Viewport
    // <= dieser CSS-Breite (z.B. "1024px") default eingeklappt.
    // Über der Schwelle bleibt der Markup-Default (i.d.R. expanded).
    collapseBelow: String,
    // #748 (Hans, 2026-06-21): Zwingt die Sektion dauerhaft aufgeklappt
    // und ignoriert dabei einen gespeicherten collapsed-State. Genutzt im
    // Edit-Modus (z.B. KI-Beschreibung), damit ein zuvor eingeklappter
    // Abschnitt das Bearbeiten-Formular nicht versteckt.
    expanded:      Boolean
  }

  connect() {
    // collapseBelow ist als Schwelle für Desktop-Layouts gedacht, in
    // denen der collapsed-Modus eine schmale Spalte daneben (Streifen)
    // ergibt. Auf Mobile (< md = 768px) wäre der Streifen-Modus
    // sinnlos, weil daneben nichts sichtbar ist; daher dort
    // force-expand.
    this._mediaMd = window.matchMedia("(min-width: 768px)")
    this._onResize = () => this.applyDesiredCollapse()
    this._mediaMd.addEventListener("change", this._onResize)

    // #232 Option A (Hans, 2026-05-31): Ein Turbo-Refresh-Morph rendert den
    // content-Target auf das Server-Default-Markup zurueck (hidden-Klasse) —
    // eine aufgeklappte Sektion klappt dabei wieder zu, weil connect() nach
    // dem Morph NICHT neu feuert. Daher auf turbo:render den gewuenschten
    // (gespeicherten) Zustand erneut anwenden. applyDesiredCollapse ist
    // idempotent, also unschaedlich bei Nicht-Morph-Renders.
    this._onTurboRender = () => this.applyDesiredCollapse()
    document.addEventListener("turbo:render", this._onTurboRender)

    this.applyDesiredCollapse()
  }

  disconnect() {
    this._mediaMd?.removeEventListener("change", this._onResize)
    if (this._onTurboRender) {
      document.removeEventListener("turbo:render", this._onTurboRender)
      this._onTurboRender = null
    }
  }

  applyDesiredCollapse() {
    // #748: Im Edit-Modus zwingend aufgeklappt — auch nach einem Turbo-
    // Morph, der sonst den gespeicherten collapsed-State reapplyt.
    if (this.expandedValue) {
      this.expand()
      this.syncCollapsedAttr()
      return
    }
    const stored = this.hasStorageKeyValue ? localStorage.getItem(this.storageKeyValue) : null
    let desiredCollapsed
    if (stored !== null) {
      desiredCollapsed = stored === "true"
    } else if (this.hasCollapseBelowValue) {
      desiredCollapsed = window.matchMedia(`(max-width: ${this.collapseBelowValue})`).matches
    } else {
      this.syncCollapsedAttr()
      return
    }

    const isCollapsed = this.contentTarget.classList.contains("hidden")
    if (desiredCollapsed !== isCollapsed) this.toggleClasses()
    this.syncCollapsedAttr()
  }

  toggle() {
    this.toggleClasses()
    this.syncCollapsedAttr()
    const collapsed = this.contentTarget.classList.contains("hidden")
    if (this.hasStorageKeyValue) {
      localStorage.setItem(this.storageKeyValue, String(collapsed))
    }
    // #145: nach jedem Toggle ein Event dispatchen, damit eine
    // Summary-Übersicht (z.B. Details/Verknüpfungen-Kurzfassung neben
    // dem Chevron-Titel) ihre Texte aus dem aktuellen DOM-Stand neu
    // berechnen kann. Event bubbelt nicht über den eigenen Container
    // hinaus (Stimulus-Default), `@self` reicht.
    this.dispatch("toggled", { detail: { collapsed } })
    // #589: Rahmen-Blitz bei jedem Toggle (1s + Ausfaden) — Klasse neu
    // starten, Reflow dazwischen, sonst re-triggert die Animation nicht.
    this.element.classList.remove("section-flash")
    void this.element.offsetWidth
    this.element.classList.add("section-flash")
  }

  // Programmatisch einklappen, falls aktuell ausgeklappt. Idempotent.
  // Speichert KEINEN Storage-Eintrag — wird vom Stack-History benutzt,
  // damit der User-Default nach einem Auto-Collapse erhalten bleibt.
  collapseIfOpen() {
    if (!this.contentTarget.classList.contains("hidden")) {
      this.toggleClasses()
      this.syncCollapsedAttr()
    }
  }

  // Spiegelbildlich: programmatisch ausklappen, falls eingeklappt.
  // Damit z.B. ein Edit-Link auch in einem collapsed Comment funktioniert.
  expand() {
    if (this.contentTarget.classList.contains("hidden")) {
      this.toggleClasses()
      this.syncCollapsedAttr()
    }
  }

  toggleClasses() {
    this.contentTarget.classList.toggle("hidden")
    if (this.hasIconTarget) this.iconTarget.classList.toggle("rotate-90")
  }

  // `data-collapsed` aufs Outer-Element schreiben, damit Tailwind-
  // data-Variants (`data-[collapsed=true]:…`, `group-data-…`) die ganze
  // Komponente umstylen können — nicht nur den Content-Target.
  syncCollapsedAttr() {
    this.element.dataset.collapsed =
      this.contentTarget.classList.contains("hidden") ? "true" : "false"
  }
}
