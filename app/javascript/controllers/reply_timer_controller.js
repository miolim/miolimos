import { Controller } from "@hotwired/stimulus"

// #533 #1 (Hans, 2026-06-07): Auto-Timer beim Antwort-Bearbeiten. Beim ersten
// aktiven Tippen / Öffnen des Edit-Felds startet (oder setzt fort) ein Timer
// für die zugehörige Aufgabe/KI; beim Abschließen (Entwurf/Senden) endet er.
//
// #588 (Hans, 2026-06-10): Zeit läuft nur, solange das Feld den Fokus hat.
// focusout (außerhalb des Forms) bzw. Fenster-Blur → Pause; erneutes
// Fokussieren/Tippen → reply_start (der Server resumt pausierte Timer).
// Die eigentliche Regel (fortsetzen vs. neu, hart beenden) liegt am Server
// (reply_start/reply_pause/reply_end); dieser Controller ist nur Auslöser.
export default class extends Controller {
  static values = { subjectType: String, subjectId: String,
                    startUrl: String, endUrl: String, pauseUrl: String }

  connect() {
    this._state = "idle"   // idle | running | paused
    this._onWindowBlur = () => this.pause()
    window.addEventListener("blur", this._onWindowBlur)
  }

  disconnect() {
    window.removeEventListener("blur", this._onWindowBlur)
  }

  begin() {
    if (this._state === "running") return
    if (!this.subjectTypeValue || !this.subjectIdValue) return
    this._state = "running"
    this._post(this.startUrlValue)
  }

  // focusout: nur pausieren, wenn der Fokus das Form wirklich verlässt —
  // Wechsel zwischen Textarea und Submit-Button ist kein Verlassen.
  pause(event) {
    if (this._state !== "running") return
    if (event && event.relatedTarget && this.element.contains(event.relatedTarget)) return
    if (!this.pauseUrlValue) return
    this._state = "paused"
    this._post(this.pauseUrlValue)
  }

  end() {
    if (this._state === "idle") return
    this._state = "idle"
    this._post(this.endUrlValue)
  }

  async _post(url) {
    try {
      await fetch(url, {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ subject_type: this.subjectTypeValue, subject_id: this.subjectIdValue })
      })
      window.dispatchEvent(new CustomEvent("time-entry:changed"))
    } catch (_) { /* ignore */ }
  }
}
