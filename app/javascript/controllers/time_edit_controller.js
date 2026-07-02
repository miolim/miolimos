import { Controller } from "@hotwired/stimulus"

// #533 #3/#4 (Hans, 2026-06-07): Start/Ende bzw. nur Dauer einer Zeitbuchung
// bearbeiten. PATCH /time_entries/:id/update_times; danach die Detail-Card
// (Ereignis-Log + Summe) frisch nachladen und den Header-Timer informieren.
export default class extends Controller {
  static targets = ["startedAt", "endedAt", "minutes", "error"]
  static values  = { url: String, cardUrl: String, destroyUrl: String }

  async destroy(e) {
    e?.preventDefault()
    if (!window.confirm(window.t("js.time_edit.confirm_delete"))) return
    try {
      const res = await fetch(this.destroyUrlValue, {
        method: "DELETE",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
      })
      if (!res.ok) { this._err(window.t("js.time_edit.delete_failed")); return }
      window.dispatchEvent(new CustomEvent("time-entry:changed"))
      this.element.closest(".stack-card")?.remove()
    } catch (_) { this._err(window.t("js.time_edit.network_error")) }
  }

  saveTimes(e) {
    e?.preventDefault()
    const body = new URLSearchParams()
    if (this.hasStartedAtTarget && this.startedAtTarget.value) body.set("started_at", this.startedAtTarget.value)
    if (this.hasEndedAtTarget && this.endedAtTarget.value)     body.set("ended_at", this.endedAtTarget.value)
    this._patch(body)
  }

  saveDuration(e) {
    e?.preventDefault()
    const m = this.hasMinutesTarget ? parseInt(this.minutesTarget.value, 10) : 0
    if (!m || m <= 0) { this._err(window.t("js.time_edit.duration_required")); return }
    const body = new URLSearchParams()
    body.set("minutes", String(m))
    this._patch(body)
  }

  async _patch(body) {
    this._clear()
    try {
      const res = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
        },
        body
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) { this._err(data.error || window.t("js.time_edit.save_failed")); return }
      window.dispatchEvent(new CustomEvent("time-entry:changed"))
      this._reloadCard()
    } catch (_) { this._err(window.t("js.time_edit.network_error")) }
  }

  async _reloadCard() {
    if (!this.cardUrlValue) return
    try {
      const res = await fetch(this.cardUrlValue, { headers: { Accept: "text/html" } })
      if (!res.ok) return
      const html = await res.text()
      const card = this.element.closest(".stack-card")
      const tpl  = document.createElement("template")
      tpl.innerHTML = html.trim()
      const fresh = tpl.content.firstElementChild
      if (card && fresh) card.replaceWith(fresh)
    } catch (_) { /* ignore */ }
  }

  _err(m) { if (this.hasErrorTarget) { this.errorTarget.textContent = m; this.errorTarget.classList.remove("hidden") } }
  _clear() { if (this.hasErrorTarget) { this.errorTarget.textContent = ""; this.errorTarget.classList.add("hidden") } }
}
