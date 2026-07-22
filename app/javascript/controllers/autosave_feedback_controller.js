import { Controller } from "@hotwired/stimulus"
import { isAutosaveTrigger, fieldDescriptor, refindField } from "lib/autosave_feedback"

// #1114 (Hans, 2026-07-22): Rueckmeldung fuer Autosave-Felder — EIN
// Controller fuer alle. Sitzt am <body> und beobachtet dokumentweit:
//
//   1. change/focusout (capture): kommt das Event von einem Autosave-
//      Feld (Inline-`requestSubmit`-Handler, siehe lib/autosave_feedback),
//      wird es pro Form als "zuletzt ausgeloest" gemerkt.
//   2. turbo:submit-end derselben Form kurz danach: Erfolg → gruenes
//      Haekchen am Feld (600 ms) + kurzer Erfolgs-Rahmen; Fehler →
//      roter Rahmen + Tooltip, bis der Wert erneut geaendert wird.
//
// Der Felder-Block wird bei vielen Autosaves per Turbo-Stream ersetzt —
// das Feedback-Ziel wird darum notfalls ueber form-action + Feldname
// neu gefunden (refindField). Die Inline-Handler der 71 Felder bleiben
// unangetastet: die Erkennung haengt am Handler selbst, neue Felder im
// selben Muster bekommen die Rueckmeldung automatisch.
export default class extends Controller {
  static FLASH_MS   = 600   // Hans-Spec: kurzes Haekchen, 600 ms
  static PENDING_MS = 3000  // change→submit-end-Korrelation: max. Abstand

  connect() {
    this._pending = new Map()   // form → { desc, el, at }
    this._activeFlash = null    // { desc, until } — laufendes Erfolgs-Haekchen
    this._activeError = null    // { desc } — stehender Fehler-Rahmen
    this._remember = (e) => {
      const el = e.target
      if (!isAutosaveTrigger(el) || !el.form) return
      this._pending.set(el.form, { desc: fieldDescriptor(el.form, el), el, at: Date.now() })
    }
    this._onSubmitEnd = (e) => this._feedback(e)
    // input (capture): Fehler-Markierung verschwindet, sobald der User
    // den Wert wieder anfasst — der naechste Save entscheidet neu.
    this._clearError = (e) => {
      // Die Markierung kann am Feld selbst ODER an seiner sichtbaren
      // Vertretung (Picker-Zeile) haengen — closest deckt beide ab.
      const marked = e.target?.closest?.(".autosave-error")
      if (marked) {
        this._activeError = null
        this._unmarkError(marked)
      }
    }
    // Turbo-Page-Morphs (Live-Broadcasts — ein Task-Save loest selbst
    // einen aus!) ersetzen Feld und Badge mitten in der Anzeige. Nach
    // jedem Render laufende Markierungen am (neu gefundenen) Feld
    // wiederherstellen — Haekchen fuer die Restzeit, Fehler dauerhaft.
    this._onRender = () => this._reapplyAfterRender()
    document.addEventListener("change",   this._remember, true)
    document.addEventListener("focusout", this._remember, true)
    document.addEventListener("input",    this._clearError, true)
    document.addEventListener("turbo:submit-end", this._onSubmitEnd)
    document.addEventListener("turbo:render", this._onRender)
  }

  disconnect() {
    document.removeEventListener("change",   this._remember, true)
    document.removeEventListener("focusout", this._remember, true)
    document.removeEventListener("input",    this._clearError, true)
    document.removeEventListener("turbo:submit-end", this._onSubmitEnd)
    document.removeEventListener("turbo:render", this._onRender)
  }

  _reapplyAfterRender() {
    if (this._activeFlash) {
      const remaining = this._activeFlash.until - Date.now()
      if (remaining > 60) {
        const field  = refindField(document, this._activeFlash.desc)
        const target = field && this._visibleTargetFor(field)
        if (target && !target.classList.contains("autosave-saved")) {
          this._showFlash(field, remaining)
        }
      } else {
        this._activeFlash = null
      }
    }
    if (this._activeError) {
      const field  = refindField(document, this._activeError.desc)
      const target = field && this._visibleTargetFor(field)
      if (target && !target.classList.contains("autosave-error")) this._markErrorStyles(field)
    }
  }

  // #1114 v3: Manche Autosave-Felder sind nach dem Save wieder
  // unsichtbar — z.B. die Picker-Zeilen der Task-Card (Input lebt in
  // einer hidden Box, der Server ersetzt den Block nach dem PATCH).
  // Die Rueckmeldung gehoert dann an die sichtbare Vertretung des
  // Feldes: die Picker-Zeile, sonst den naechsten sichtbaren Vorfahren.
  _visibleTargetFor(field) {
    const visible = el => !!el && typeof el.getBoundingClientRect === "function" &&
                          el.getBoundingClientRect().width > 0
    if (visible(field)) return field
    let el = field.closest?.('[data-controller~="picker-toggle"]') || field.form || field
    while (el && !visible(el)) el = el.parentElement
    return el
  }

  _feedback(event) {
    const form  = event.target
    const entry = this._pending.get(form)
    if (!entry) return
    this._pending.delete(form)
    if (Date.now() - entry.at > this.constructor.PENDING_MS) return
    const success = !!event.detail?.success
    // Kleine Verzoegerung: die Turbo-Stream-Antwort ersetzt den Felder-
    // Block etwa zeitgleich mit submit-end — erst danach das (ggf. neue)
    // Feld suchen, sonst haengt das Haekchen am toten Knoten.
    setTimeout(() => {
      const field = entry.el?.isConnected ? entry.el : refindField(document, entry.desc)
      if (!field) return
      if (success) this._flashSuccess(field)
      else         this._markError(field)
    }, 80)
  }

  _flashSuccess(field) {
    // Nur aufraeumen, wenn WIR den Fehler-Zustand gesetzt hatten — sonst
    // wuerde ein regulaerer title (z.B. Tooltip eines Datumsfelds) beim
    // ersten erfolgreichen Save verschwinden. Die Markierung kann am
    // Feld oder an seiner sichtbaren Vertretung haengen.
    this._activeError = null
    const marked = field.closest?.(".autosave-error") || (this._visibleTargetFor(field)?.classList.contains("autosave-error") ? this._visibleTargetFor(field) : null)
    if (marked) this._unmarkError(marked)
    this._activeFlash = {
      desc:  fieldDescriptor(field.form, field),
      until: Date.now() + this.constructor.FLASH_MS
    }
    this._showFlash(field, this.constructor.FLASH_MS)
  }

  // Klasse + Badge fuer `ms` Millisekunden anzeigen — auch fuer die
  // RESTZEIT nach einem Morph (_reapplyAfterRender) wiederverwendet.
  // Ziel ist das Feld selbst oder, wenn es (wieder) unsichtbar ist,
  // seine sichtbare Vertretung (_visibleTargetFor).
  _showFlash(field, ms) {
    const target = this._visibleTargetFor(field)
    if (!target) return
    target.classList.add("autosave-saved")
    setTimeout(() => { if (target.isConnected) target.classList.remove("autosave-saved") }, ms)
    const r = target.getBoundingClientRect()
    if (!r.width) return
    const badge = document.createElement("div")
    badge.className = "autosave-check-badge"
    badge.setAttribute("aria-hidden", "true")
    badge.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" class="w-3 h-3"><path d="M20 6 9 17l-5-5"/></svg>`
    badge.style.left = `${Math.round(Math.max(r.left, r.right - 22))}px`
    badge.style.top  = `${Math.round(r.top + r.height / 2 - 9)}px`
    document.body.appendChild(badge)
    setTimeout(() => badge.remove(), ms + 60)
  }

  _markError(field) {
    this._activeError = { desc: fieldDescriptor(field.form, field) }
    this._markErrorStyles(field)
  }

  _markErrorStyles(field) {
    const target = this._visibleTargetFor(field)
    if (!target) return
    target.classList.add("autosave-error")
    // Tooltip erklaert den roten Rahmen; Original-title (falls einer da
    // war) merken und beim Aufraeumen zuruecksetzen.
    if (target.title && !target.dataset.autosavePrevTitle) {
      target.dataset.autosavePrevTitle = target.title
    }
    target.title = window.t ? window.t("js.autosave.failed") : "Speichern fehlgeschlagen"
  }

  _unmarkError(field) {
    field.classList.remove("autosave-error")
    if (field.dataset.autosavePrevTitle) {
      field.title = field.dataset.autosavePrevTitle
      delete field.dataset.autosavePrevTitle
    } else if (field.title) {
      field.removeAttribute("title")
    }
  }
}
