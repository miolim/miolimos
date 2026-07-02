import { Controller } from "@hotwired/stimulus"

// #533 Phase 1b (Hans, 2026-06-07): Header-Timer + Quick-Add-Popup.
// Eine Uhr als einzige Wahrheit: zeigt den laufenden Timer des current_actor
// (egal von wo gestartet — Card-Button, Popup), tickt clientseitig ab
// started_at und kann hier gestoppt werden. Das Popup startet einen Timer
// ("jetzt") oder trägt eine fertige Buchung nach (Datum + Dauer). Quelle der
// Wahrheit ist immer der Server (GET running), die Uhr ist nur Anzeige.
export default class extends Controller {
  static targets = ["bar", "popup",
                    "topic", "note", "billable",
                    "manualFields", "startedAt", "minutes", "submit", "error",
                    "subjectRow", "subjectLabel", "subjectTopics", "removeOthers"]
  static values  = { runningUrl: String, createUrl: String, stopUrl: String }

  connect() {
    this._mode = "timer"
    this._timer = null
    this._startedAt = null
    this._subject = null        // { type, id } beim Start von einer Card
    this._pickedTopic = null    // bei Mehrfach-Topic-Auswahl
    this._onChanged = () => this.refresh()
    this._onStartSubject = (e) => this._startForSubject(e.detail)
    window.addEventListener("time-entry:changed", this._onChanged)
    window.addEventListener("time-timer:start-subject", this._onStartSubject)
    this.refresh()
  }

  disconnect() {
    window.removeEventListener("time-entry:changed", this._onChanged)
    window.removeEventListener("time-timer:start-subject", this._onStartSubject)
    this._stopTick()
  }

  // ── Start von einer Aufgaben-/KI-Card (Hans-Regeln) ─────────────
  _startForSubject({ subjectType, subjectId, label, topics }) {
    this._subject = { type: subjectType, id: subjectId }
    const list = Array.isArray(topics) ? topics : []
    if (list.length === 1) {
      // Genau ein Projekt → sofort starten.
      this._post(this.createUrlValue, this._subjectBody({ topicId: list[0].id }))
      return
    }
    // 0 oder mehrere → Popup mit Projekt-Wahl.
    this._mode = "timer"
    this._pickedTopic = null
    this._openSubjectPopup(label, list)
  }

  _openSubjectPopup(label, topics) {
    this._clearError()
    if (this.hasSubjectRowTarget) {
      this.subjectRowTarget.classList.remove("hidden")
      if (this.hasSubjectLabelTarget) this.subjectLabelTarget.textContent = label || ""
    }
    // Mehrere Topics der Aufgabe/KI als Buttons; sonst den normalen Picker.
    if (this.hasSubjectTopicsTarget) {
      this.subjectTopicsTarget.innerHTML = ""
      if (topics.length > 1) {
        topics.forEach((t) => {
          const b = document.createElement("button")
          b.type = "button"
          b.textContent = t.name
          b.className = "px-2 py-0.5 rounded border border-slate-200 text-xs hover:bg-emerald-50 cursor-pointer"
          b.addEventListener("click", () => {
            this._pickedTopic = String(t.id)
            this.subjectTopicsTarget.querySelectorAll("button").forEach((x) =>
              x.classList.remove("bg-emerald-100", "border-emerald-300"))
            b.classList.add("bg-emerald-100", "border-emerald-300")
          })
          this.subjectTopicsTarget.appendChild(b)
        })
        // subjectTopics ist immer ein flex-Container; leer = unsichtbar.
        if (this.hasRemoveOthersTarget) this.removeOthersTarget.closest("label")?.classList.remove("hidden")
        if (this.hasTopicTarget) this.topicTarget.classList.add("hidden")
      } else {
        if (this.hasRemoveOthersTarget) this.removeOthersTarget.closest("label")?.classList.add("hidden")
        if (this.hasTopicTarget) this.topicTarget.classList.remove("hidden")
      }
    }
    this.popupTarget.classList.remove("hidden")
  }

  _subjectBody({ topicId }) {
    const body = new URLSearchParams()
    body.set("mode", "timer")
    body.set("topic_id", topicId)
    body.set("subject_type", this._subject.type)
    body.set("subject_id", this._subject.id)
    body.set("link_topic", "1")  // Projekt mit der Aufgabe/KI verknüpfen
    return body
  }

  // ── Anzeige ─────────────────────────────────────────────────────
  async refresh() {
    try {
      const res = await fetch(this.runningUrlValue, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      const data = await res.json()
      this._render(data)
    } catch (_) { /* offline: Anzeige unverändert lassen */ }
  }

  // Rendert das Regal: ein Chip je aktivem Timer (laufend + pausiert).
  _render(data) {
    if (!this.hasBarTarget) return
    const active = Array.isArray(data.active) ? data.active : []
    this.barTarget.innerHTML = ""
    active.forEach((e) => this.barTarget.appendChild(this._chip(e)))
    if (active.some((e) => e.running)) this._startTick()
    else this._stopTick()
    this._tick()
  }

  _chip(e) {
    const running = !!e.running
    const chip = document.createElement("div")
    chip.className = "flex items-center gap-1 rounded border px-1.5 py-0.5 text-xs " +
      (running ? "bg-emerald-50 border-emerald-200" : "bg-slate-50 border-slate-200")

    const dot = document.createElement("span")
    dot.className = "w-1.5 h-1.5 rounded-full " + (running ? "bg-emerald-500 animate-pulse" : "bg-slate-400")
    chip.appendChild(dot)

    const clock = document.createElement("span")
    clock.className = "font-mono tabular-nums " + (running ? "text-emerald-800" : "text-slate-600")
    clock.dataset.timerElapsed = "1"
    clock.dataset.accumulated  = String(e.accumulated_seconds || 0)
    clock.dataset.runningSince = running && e.running_since ? String(new Date(e.running_since).getTime()) : ""
    clock.textContent = this._fmt(this._elapsedSecs(clock))
    chip.appendChild(clock)

    const labelText = this._chipLabel(e)
    if (labelText) {
      const lab = document.createElement("span")
      lab.className = "hidden md:inline max-w-[10rem] truncate " + (running ? "text-emerald-700" : "text-slate-500")
      lab.textContent = labelText
      chip.appendChild(lab)
    }

    if (running) chip.appendChild(this._chipBtn("⏸", window.t("js.time_timer.pause"), () => this._member(e.id, "pause")))
    else         chip.appendChild(this._chipBtn("▶", window.t("js.time_timer.resume"), () => this._member(e.id, "resume")))
    chip.appendChild(this._chipBtn("■", window.t("js.time_timer.finish"), () => this._member(e.id, "finish")))
    return chip
  }

  _chipBtn(symbol, title, onClick) {
    const b = document.createElement("button")
    b.type = "button"
    b.title = title
    b.setAttribute("aria-label", title)
    b.textContent = symbol
    b.className = "px-0.5 leading-none text-slate-500 hover:text-slate-900 cursor-pointer"
    b.addEventListener("click", (e) => { e.preventDefault(); onClick() })
    return b
  }

  _chipLabel(e) {
    const parts = []
    if (e.subject?.label) parts.push(e.subject.label)
    else if (e.note)      parts.push(e.note)
    if (e.topic?.name)    parts.push(e.topic.name)
    return parts.join(" · ")
  }

  _elapsedSecs(clockEl) {
    const base  = parseInt(clockEl.dataset.accumulated, 10) || 0
    const since = clockEl.dataset.runningSince ? parseInt(clockEl.dataset.runningSince, 10) : 0
    return since ? base + Math.max(0, Math.floor((Date.now() - since) / 1000)) : base
  }

  _fmt(secs) {
    const pad = (n) => String(n).padStart(2, "0")
    return `${pad(Math.floor(secs / 3600))}:${pad(Math.floor((secs % 3600) / 60))}:${pad(secs % 60)}`
  }

  async _member(id, action) {
    try {
      const res = await fetch(`${this.createUrlValue}/${id}/${action}`, {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" }
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) return
      this._render(data)
    } catch (_) { /* ignore */ }
  }

  _startTick() {
    this._stopTick()
    this._tick()
    this._timer = setInterval(() => this._tick(), 1000)
  }
  _stopTick() {
    if (this._timer) { clearInterval(this._timer); this._timer = null }
  }
  _tick() {
    if (!this.hasBarTarget) return
    this.barTarget.querySelectorAll("[data-timer-elapsed]").forEach((el) => {
      el.textContent = this._fmt(this._elapsedSecs(el))
    })
  }

  // ── Popup ───────────────────────────────────────────────────────
  togglePopup(event) {
    event?.preventDefault()
    const willOpen = this.popupTarget.classList.contains("hidden")
    if (willOpen) {
      this._resetSubject()   // normaler (kontextloser) Modus
      this._clearError()
    }
    this.popupTarget.classList.toggle("hidden")
    if (willOpen && this.hasTopicTarget) this.topicTarget.focus()
  }
  closePopup() { this.popupTarget.classList.add("hidden") }

  // Setzt den Card-Start-Modus zurück → normales Projekt-Picker-Popup.
  _resetSubject() {
    this._subject = null
    this._pickedTopic = null
    if (this.hasSubjectRowTarget) this.subjectRowTarget.classList.add("hidden")
    if (this.hasSubjectTopicsTarget) this.subjectTopicsTarget.innerHTML = ""
    if (this.hasRemoveOthersTarget) {
      this.removeOthersTarget.checked = false
      this.removeOthersTarget.closest("label")?.classList.add("hidden")
    }
    if (this.hasTopicTarget) this.topicTarget.classList.remove("hidden")
  }

  setTimerMode(event) { event?.preventDefault(); this._setMode("timer") }
  setManualMode(event) { event?.preventDefault(); this._setMode("manual") }
  _setMode(mode) {
    this._mode = mode
    if (this.hasManualFieldsTarget) {
      this.manualFieldsTarget.classList.toggle("hidden", mode !== "manual")
    }
    if (this.hasSubmitTarget) {
      this.submitTarget.textContent = mode === "manual" ? window.t("js.time_timer.save_entry") : window.t("js.time_timer.start_timer")
    }
  }

  async submit(event) {
    event?.preventDefault()
    this._clearError()
    // Topic: bei Mehrfach-Auswahl der gewählte Button, sonst der Select.
    const topicId = this._pickedTopic || (this.hasTopicTarget ? this.topicTarget.value : "")
    if (!topicId) { this._showError(window.t("js.time_timer.project_required")); return }
    const body = new URLSearchParams()
    body.set("mode", this._mode)
    body.set("topic_id", topicId)
    if (this.hasNoteTarget && this.noteTarget.value.trim()) body.set("note", this.noteTarget.value.trim())
    if (this.hasBillableTarget && this.billableTarget.checked) body.set("billable", "1")
    if (this._subject) {
      body.set("subject_type", this._subject.type)
      body.set("subject_id", this._subject.id)
      body.set("link_topic", "1")
      if (this.hasRemoveOthersTarget && this.removeOthersTarget.checked) body.set("replace_topics", "1")
    }
    if (this._mode === "manual") {
      if (this.hasStartedAtTarget && this.startedAtTarget.value) body.set("started_at", this.startedAtTarget.value)
      const mins = this.hasMinutesTarget ? parseInt(this.minutesTarget.value, 10) : 0
      if (!mins || mins <= 0) { this._showError(window.t("js.time_timer.duration_required")); return }
      body.set("minutes", String(mins))
    }
    await this._post(this.createUrlValue, body)
  }

  async stop(event) {
    event?.preventDefault()
    await this._post(this.stopUrlValue, new URLSearchParams())
  }

  async _post(url, body) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) { this._showError(data.error || window.t("js.time_timer.save_failed")); return }
      this.closePopup()
      this._resetSubject()
      if (this.hasNoteTarget) this.noteTarget.value = ""
      this._render(data)
      // Andere Stellen (Card-Buttons, Übersichten) informieren.
      window.dispatchEvent(new CustomEvent("time-entry:changed"))
    } catch (_) {
      this._showError(window.t("js.time_timer.network_error"))
    }
  }

  _showError(msg) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = msg
    this.errorTarget.classList.remove("hidden")
  }
  _clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }
}
