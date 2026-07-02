// #803 (aus #801 R5): Edit-Mode-Logik (Edit-Form finden, Submit mit keep_editing, Edit/Preview-Toggle + Mode-Swap).
// Aus blade_stack_controller.js extrahiert — wird als Mixin aufs
// Prototype gemixt (Muster #378/#529), damit `this` weiterhin den
// Stack-Controller meint (Targets, Values, Helpers). Reines Code-Move.
//
// Enthaltene Methoden: activeEditForm · submitForm · toggleEditPreview · swapToEditMode

export const BladeStackEditModeMixin = {
// Findet das offene Edit-Form der aktiven Card. Liefert nil, wenn
// die aktive Card im Preview-Mode ist.
activeEditForm() {
  const card = this.activeCard()
  return card?.querySelector('form[id^="knowledge_edit_form_"]') ||
         card?.querySelector("form[action='/knowledge_items']")
},

submitForm(form, { keepEditing }) {
  if (keepEditing) {
    // Hidden-Field für keep_editing setzen — Server rendert dann
    // wieder im Edit-Mode statt Preview.
    let kf = form.querySelector("input[name='keep_editing']")
    if (!kf) {
      kf = document.createElement("input")
      kf.type = "hidden"
      kf.name = "keep_editing"
      form.appendChild(kf)
    }
    kf.value = "1"
  } else {
    form.querySelector("input[name='keep_editing']")?.remove()
  }
  form.requestSubmit()
},

async toggleEditPreview() {
  const card = this.activeCard()
  if (!card) return
  // Im Edit-Mode: speichern + zurück zu Preview (sonst Datenverlust-
  // Risiko). Im Preview-Mode: Edit-Frame laden, Cursor ans Ende.
  const form = card.querySelector('form[id^="knowledge_edit_form_"]')
  if (form) {
    this.submitForm(form, { keepEditing: false })
    return
  }
  const uuid = card.dataset.uuid
  if (!uuid || uuid === "new") return
  await this.swapToEditMode(uuid)
},

// Holt den Edit-Frame fürs gegebene KI vom Server, ersetzt den Frame
// in der aktiven Card in-place. Cursor landet am Ende der Textarea —
// damit man direkt weiterschreiben kann statt erst ans Ende klicken.
async swapToEditMode(uuid) {
  const res = await fetch(`/knowledge_items/${uuid}/edit?in_stack=1`, {
    headers: { "Accept": "text/html" }
  })
  if (!res.ok) return
  const html = await res.text()
  const doc  = new DOMParser().parseFromString(html, "text/html")
  const fresh = doc.querySelector(`turbo-frame#knowledge_detail_${uuid}`)
  const old   = document.querySelector(`turbo-frame#knowledge_detail_${uuid}`)
  if (!fresh || !old) return
  old.replaceWith(fresh)
  const textarea = fresh.querySelector('textarea[name*="content"]')
  if (textarea) {
    textarea.focus()
    const end = textarea.value.length
    textarea.setSelectionRange(end, end)
    // Scroll an das Ende der Textarea, falls länger als Viewport.
    textarea.scrollTop = textarea.scrollHeight
  }
}

// #224 6f-3: Horizontaler Wheel-Input → eine Geste = ein Focus-Step.
// Mausrad (deltaY) und Trackpad-Swipe (deltaX) werden gleichermassen
// betrachtet; deltaX gewinnt, falls beides feuert (Trackpad-2-Finger).
// Threshold (THRESH) verhindert Mikro-Triggers durch Trail-Friction.
// Lock (200ms) verhindert mehrere Steps in einer einzigen schnellen
// Geste (Trackpad liefert nach dem Finger-Lift noch deltas, wir
// ignorieren die).
// _handleWheel liegt in BladeStackScrollMixin (#529).

}
