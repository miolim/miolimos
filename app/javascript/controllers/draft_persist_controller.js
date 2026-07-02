import { Controller } from "@hotwired/stimulus"

// #698 (Hans, 2026-06-14): getippten Text lokal als Entwurf sichern
// (localStorage), damit er auch bei abgelaufener Session, geschlossenem
// Browser oder Tab-Wechsel NICHT verloren geht — der Server-Auto-Save
// (sendBeacon) scheitert genau dann, wenn die Session weg ist. Beim
// erneuten Öffnen des Bearbeiten-Felds wird ein noch nicht gespeicherter
// Entwurf wiederhergestellt; beim erfolgreichen Speichern verworfen.
//
// Markup (draft-persist MUSS vor cm6-editor stehen, damit die
// Wiederherstellung vor der CM6-Initialisierung greift):
//   <div data-controller="draft-persist cm6-editor …"
//        data-draft-persist-key-value="ki.<uuid>.content">
//     <textarea data-draft-persist-target="input" data-cm6-editor-target="textarea">…</textarea>
//   </div>
export default class extends Controller {
  static targets = ["input"]
  static values  = { key: String }

  connect() {
    this._k = `draft:${this.keyValue}`
    this._restore()
    this._onInput  = () => this._scheduleSave()
    this._onSubmit = (e) => { if (e.detail?.success !== false) this._clear() }
    this._onHide   = () => this._saveNow()
    // turbo:submit-end feuert auf dem <form> und bubbelt NACH OBEN. Der
    // Wrapper-div ist ein KIND des Formulars, das Event erreicht ihn also
    // nie — wir müssen am Formular selbst lauschen, sonst bleibt der
    // Entwurf nach „Als Entwurf speichern"/„Veröffentlichen" liegen und
    // wird im neu gerenderten (leeren) Feld als „nicht gespeichert"
    // wiederhergestellt (#698, Hans). Fallback: das Element selbst.
    this._form = this.inputTarget.form || this.element
    this.inputTarget.addEventListener("input", this._onInput)
    this._form.addEventListener("turbo:submit-end", this._onSubmit)
    window.addEventListener("pagehide", this._onHide)
    document.addEventListener("turbo:before-visit", this._onHide)
  }

  disconnect() {
    this.inputTarget.removeEventListener("input", this._onInput)
    this._form.removeEventListener("turbo:submit-end", this._onSubmit)
    window.removeEventListener("pagehide", this._onHide)
    document.removeEventListener("turbo:before-visit", this._onHide)
    clearTimeout(this._t)
  }

  // Gespeicherten Entwurf in das Textarea zurückspielen (sofern er sich vom
  // aktuellen Server-Stand unterscheidet) — VOR der CM6-Initialisierung.
  _restore() {
    let saved
    try { saved = localStorage.getItem(this._k) } catch (e) { return }
    if (saved == null || saved === this.inputTarget.value) return
    this.inputTarget.value = saved
    // autosize/dirty-warn informieren (cm6 liest den Wert in seinem connect).
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this._showHint()
  }

  _scheduleSave() {
    clearTimeout(this._t)
    this._t = setTimeout(() => this._saveNow(), 500)
  }

  _saveNow() {
    // Beim Verwerfen NICHT erneut sichern — sonst schreibt der pagehide
    // des reload() den gerade verworfenen Entwurf zurück (#698, Hans).
    if (this._discarding) return
    try {
      const v = this.inputTarget.value
      if (v && v.length) localStorage.setItem(this._k, v)
    } catch (e) { /* localStorage voll/blockiert — still ignorieren */ }
  }

  _clear() {
    try { localStorage.removeItem(this._k) } catch (e) {}
    this.element.querySelector(":scope > .draft-restored-hint")?.remove()
  }

  // „verwerfen": Entwurf endgültig löschen und das Feld sauber auf den
  // Server-Stand zurücksetzen. Statt eines kompletten Page-Reloads
  // aktualisieren wir nur das Blade (wie „Card neu laden", #698 Hans):
  // refreshCard holt die Card frisch vom Server, der neu verbundene
  // Controller liest das bereits geleerte localStorage → kein Restore,
  // CM6 initialisiert sauber. Fallback (z.B. Quick-Create-Formular ohne
  // Blade): Hide-Listener kappen + Full-Reload.
  _discard() {
    this._discarding = true
    clearTimeout(this._t)
    try { localStorage.removeItem(this._k) } catch (e) {}
    const card      = this.element.closest(".stack-card")
    const reloadBtn = card?.querySelector('[data-action~="click->blade-stack#reloadCard"]')
    if (reloadBtn) {
      reloadBtn.click()
    } else {
      window.removeEventListener("pagehide", this._onHide)
      document.removeEventListener("turbo:before-visit", this._onHide)
      window.location.reload()
    }
  }

  _showHint() {
    if (this.element.querySelector(":scope > .draft-restored-hint")) return
    const hint = document.createElement("div")
    hint.className = "draft-restored-hint text-[11px] text-amber-800 bg-amber-50 border border-amber-200 rounded px-2 py-1 mb-1 flex items-center gap-2"
    hint.append("Nicht gespeicherter Entwurf wiederhergestellt.")
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "underline hover:no-underline cursor-pointer"
    btn.textContent = "verwerfen"
    btn.addEventListener("click", () => this._discard())
    hint.appendChild(btn)
    this.element.prepend(hint)
  }
}
