import { Controller } from "@hotwired/stimulus"

// #355 (Hans, 2026-05-25): Voreinstellungen fuer den Quick-Create-
// Task-Slot in der Systemrow (Topic + Zugewiesen), localStorage-
// persistent.
//
// #641 (Hans, 2026-06-12): statt EINEM impliziten Default gibt es
// jetzt VIER benannte Presets (cat/squirrel/bird/fish) als Icon-Reihe.
// Klick auf ein Tier aktiviert sein Preset (laedt Topic+Zugewiesen);
// Aenderungen an den Selects speichern in das AKTIVE Preset. Das
// zuletzt aktive Preset wird gemerkt und beim naechsten Aufruf
// wiederhergestellt.
//
// Storage-Keys:
//   quickadd.task.preset                  — Name des aktiven Presets
//   quickadd.task.preset.<name>.topic_id
//   quickadd.task.preset.<name>.assignee_id
// Legacy (#355): quickadd.task.topic_id / .assignee_id — werden einmalig
// ins cat-Preset uebernommen.
export default class extends Controller {
  static targets = ["topic", "assignee", "preset"]

  static BASE    = "quickadd.task"
  static PRESETS = ["cat", "squirrel", "bird", "fish"]

  connect() {
    this._migrateLegacy()
    this.active = this._get(`${this.constructor.BASE}.preset`) || "cat"
    if (!this.constructor.PRESETS.includes(this.active)) this.active = "cat"
    this._applyPreset(this.active)
    this._highlight()
    // #367: Nach Form-Submit reseted Turbo das <form> auf "". Vorbeugen:
    // turbo:submit-end → aktives Preset erneut anwenden.
    this._onSubmitEnd = () => {
      requestAnimationFrame(() => { this._applyPreset(this.active); this._highlight() })
    }
    this.element.addEventListener("turbo:submit-end", this._onSubmitEnd)
  }

  disconnect() {
    if (this._onSubmitEnd) this.element.removeEventListener("turbo:submit-end", this._onSubmitEnd)
  }

  // Klick auf ein Tier-Icon: Preset aktivieren + dessen Werte laden.
  selectPreset(event) {
    const name = event.currentTarget.dataset.preset
    if (!this.constructor.PRESETS.includes(name)) return
    this.active = name
    this._set(`${this.constructor.BASE}.preset`, name)
    this._applyPreset(name)
    this._highlight()
  }

  saveTopic()    { this._persist(this.hasTopicTarget && this.topicTarget,       "topic_id") }
  saveAssignee() { this._persist(this.hasAssigneeTarget && this.assigneeTarget, "assignee_id") }

  _applyPreset(name) {
    this._restoreSelect(this.hasTopicTarget    && this.topicTarget,    `${this.constructor.BASE}.preset.${name}.topic_id`)
    this._restoreSelect(this.hasAssigneeTarget && this.assigneeTarget, `${this.constructor.BASE}.preset.${name}.assignee_id`)
  }

  _highlight() {
    this.presetTargets.forEach(btn => {
      const on = btn.dataset.preset === this.active
      btn.classList.toggle("bg-emerald-100", on)
      btn.classList.toggle("text-emerald-800", on)
      btn.classList.toggle("ring-1", on)
      btn.classList.toggle("ring-emerald-400", on)
      btn.classList.toggle("text-slate-400", !on)
    })
  }

  _persist(el, field) {
    if (!el) return
    this._set(`${this.constructor.BASE}.preset.${this.active}.${field}`, el.value ?? "")
  }

  _restoreSelect(el, key) {
    if (!el) return
    const v = this._get(key)
    // Kein gespeicherter Wert → leer ("kein Topic" / "mir").
    const target = v === null ? "" : v
    const opt = Array.from(el.options).find(o => o.value === target)
    el.value = opt ? target : ""
  }

  // Einmalige Uebernahme der alten Einzel-Keys (#355) ins cat-Preset.
  _migrateLegacy() {
    const base = this.constructor.BASE
    const oldTopic    = this._get(`${base}.topic_id`)
    const oldAssignee = this._get(`${base}.assignee_id`)
    if (oldTopic === null && oldAssignee === null) return
    if (this._get(`${base}.preset.cat.topic_id`) === null && oldTopic !== null) {
      this._set(`${base}.preset.cat.topic_id`, oldTopic)
    }
    if (this._get(`${base}.preset.cat.assignee_id`) === null && oldAssignee !== null) {
      this._set(`${base}.preset.cat.assignee_id`, oldAssignee)
    }
    try {
      localStorage.removeItem(`${base}.topic_id`)
      localStorage.removeItem(`${base}.assignee_id`)
    } catch (_e) {}
  }

  _get(key) {
    try { return localStorage.getItem(key) } catch (_e) { return null }
  }

  _set(key, value) {
    try { localStorage.setItem(key, value) } catch (_e) {}
  }
}
