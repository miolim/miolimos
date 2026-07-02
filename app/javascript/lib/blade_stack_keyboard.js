// #529 (Hans, 2026-06-06): Tastatur-Logik aus blade_stack_controller.js
// ausgelagert (Refactoring-Schritt 5). Globaler Keydown-Handler (Vim-g-Chords,
// Cmd/Ctrl-Shortcuts, Alt-Trail, Card-Move/-Collapse/-Close) plus die
// Shortcut-Hilfe und der isTextEditing-Helfer. Wird als Mixin aufs Prototype
// gemixt — der in connect() gebundene `this.keyHandler = e => this.handleKeydown(e)`
// löst weiter über die Prototype-Chain auf. `this`-gebunden, reines Code-Move.
//
// Enthaltene Methoden:
//   handleKeydown     — globaler Keydown-Dispatch (alle Stack-Shortcuts)
//   isTextEditing     — Ziel ist Eingabefeld? (Shortcuts dann unterdrücken)
//   openShortcutHelp  — Modal mit der Shortcut-Übersicht (this-unabhängig)

export const BladeStackKeyboardMixin = {
  handleKeydown(event) {
    const mod   = event.metaKey || event.ctrlKey
    const inText = this.isTextEditing(event.target)

    // #463 (Hans, 2026-06-02): Vim-artige g-Chords auf der fokussierten
    // Card (ausserhalb von Textfeldern, ohne Modifier):
    //   g c -> fokussierte Card schliessen
    //   g d -> Done/not-Done der fokussierten Task-Card togglen
    if (!inText && !mod && !event.altKey && !event.shiftKey) {
      if (this._gPending) {
        this._gPending = false
        if (this._gTimer) { clearTimeout(this._gTimer); this._gTimer = null }
        const active = this.activeCard()
        if (active && event.key === "c") {
          event.preventDefault(); this._closeCardElement(active); return
        }
        if (active && event.key === "d") {
          const btn = active.querySelector("[data-task-done-toggle]")
          if (btn) { event.preventDefault(); btn.click() }
          return
        }
        // anderer Key -> Chord verworfen, normal weiterverarbeiten.
      }
      if (event.key === "g") {
        this._gPending = true
        if (this._gTimer) clearTimeout(this._gTimer)
        this._gTimer = setTimeout(() => { this._gPending = false }, 1200)
        return
      }
    }

    // ? — Shortcut-Übersicht (außerhalb von Textfeldern).
    if (!inText && event.key === "?") {
      event.preventDefault()
      this.openShortcutHelp()
      return
    }

    // Esc — Edit-Mode der aktiven Card verlassen (Cancel-Link klicken).
    if (event.key === "Escape" && inText) {
      const card = event.target.closest(".stack-card")
      if (card) {
        const cancel = card.querySelector('a[title="Abbrechen"], a[aria-label="Abbrechen"]')
        if (cancel) { event.preventDefault(); cancel.click() }
      }
      return
    }

    // #293 follow-up v3 (Hans, 2026-05-24): Cmd/Ctrl+Shift+←/→ — die
    // aktive Card im Stack EINE Position nach links/rechts verschieben.
    // Vor dem Cmd/Ctrl-Block, damit die Shift-Variante zuerst greift,
    // bevor das normale Cmd/Ctrl+Alt+←/→ den Active-Wechsel zieht.
    if (mod && event.shiftKey && (event.key === "ArrowLeft" || event.key === "ArrowRight")) {
      event.preventDefault()
      this._moveActiveCardPosition(event.key === "ArrowRight" ? +1 : -1)
      return
    }

    // Cmd/Ctrl-Modifier-Shortcuts.
    if (mod) {
      // Cmd/Ctrl+S — speichern, im Edit-Mode bleiben.
      if (event.key.toLowerCase() === "s") {
        const form = this.activeEditForm()
        if (form) {
          event.preventDefault()
          this.submitForm(form, { keepEditing: true })
        }
        return
      }
      // Cmd/Ctrl+Enter — speichern, zurück zu Preview.
      if (event.key === "Enter") {
        const form = this.activeEditForm()
        if (form) {
          event.preventDefault()
          this.submitForm(form, { keepEditing: false })
        }
        return
      }
      // Cmd/Ctrl+E — Edit ↔ Preview Toggle.
      if (event.key.toLowerCase() === "e") {
        event.preventDefault()
        this.toggleEditPreview()
        return
      }
      // Cmd/Ctrl+Alt+←/→ — aktive Card im Stack wechseln.
      if (event.altKey && (event.key === "ArrowLeft" || event.key === "ArrowRight")) {
        event.preventDefault()
        this.moveActive(event.key === "ArrowRight" ? +1 : -1)
        return
      }
      // #293 v2 (Hans): Cmd/Ctrl+Alt+↑ — kontextabhaengig:
      //   - aktive Card ist COLLAPSED → expand (Collapse-Toggle)
      //   - aktive Card ist EXPANDED  → schliessen
      if (event.altKey && event.key === "ArrowUp") {
        const active = this.activeCard()
        if (active) {
          event.preventDefault()
          if (active.dataset.collapsed === "true") {
            const spine = active.querySelector(".stack-spine")
            this.toggleCollapse({
              preventDefault: () => {},
              currentTarget: spine || active
            })
          } else {
            this._closeCardElement(active)
          }
        }
        return
      }
      // #293 v2: Cmd/Ctrl+Alt+↓ — aktive Card collapse (NUR collapse,
      // kein toggle). Wenn schon collapsed: no-op (Hans-Spec).
      if (event.altKey && event.key === "ArrowDown") {
        const active = this.activeCard()
        if (active && active.dataset.collapsed !== "true") {
          event.preventDefault()
          const spine = active.querySelector(".stack-spine")
          this.toggleCollapse({
            preventDefault: () => {},
            currentTarget: spine || active
          })
        }
        return
      }
    }

    // Alt+←/→ — Trail (Stack-State zurück/vor). Nur wenn KEIN Cmd/Ctrl
    // dabei ist (das hatten wir oben schon behandelt).
    if (event.altKey && !mod) {
      if (event.key === "ArrowLeft")  { event.preventDefault(); this.stepTrail(-1) }
      if (event.key === "ArrowRight") { event.preventDefault(); this.stepTrail(+1) }
      // #289: Alt+C schliesst die aktive Card. Nur wenn nicht in einem
      // Textfeld (sonst kollidiert's mit Browser-Default oder dem User-
      // Tippen). Findet die aktive Card, dispatcht den gleichen close-
      // Flow wie das Schliessen-Kreuz.
      if (!inText && event.key.toLowerCase() === "c") {
        const active = this.activeCard()
        if (active) {
          event.preventDefault()
          this._closeCardElement(active)
        }
      }
    }
  },

  isTextEditing(el) {
    if (!el) return false
    const tag = el.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || el.isContentEditable
  },

  // #759 (Hans, 2026-06-23): Das Modal lebt jetzt im shortcut-help-Controller
  // (Topbar-Icon + Taste „?"). Hier nur das Event dispatchen, damit der
  // `?`-Trigger weiter funktioniert — der Controller (Topbar) fängt es ab.
  openShortcutHelp() {
    window.dispatchEvent(new CustomEvent("shortcut-help:open"))
  }
}
