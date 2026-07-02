import { Controller } from "@hotwired/stimulus"

// Schaltet im Inbox-Run-Picker das zweite Dropdown (Prompt-Vorlage)
// und den Hilfstext beim Wechsel des Processors um.
//
// Konvention im Markup:
//   - <select data-run-picker-target="processor">
//   - <div    data-run-picker-target="templateBlock">  ← AiTransform-only
//   - <p      data-run-picker-target="hint">           ← description
//   - Hilfstexte pro Processor-Kind als
//     data-run-picker-descriptions-value='{"youtube_transcribe":"…"}'
//
// Der templateBlock ist sichtbar, wenn der gewählte Processor
// "ai_transform" ist (bzw. der Wert in templateForValue steht).
export default class extends Controller {
  static targets = ["processor", "templateBlock", "hint"]
  static values  = {
    descriptions:   Object,
    templateFor:    { type: String, default: "ai_transform" }
  }

  connect() { this.update() }

  onChange() { this.update() }

  update() {
    const kind = this.processorTarget.value
    if (this.hasTemplateBlockTarget) {
      this.templateBlockTarget.classList.toggle("hidden", kind !== this.templateForValue)
    }
    if (this.hasHintTarget) {
      this.hintTarget.textContent = this.descriptionsValue[kind] || ""
    }
  }
}
