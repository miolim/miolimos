// #529 (Hans, 2026-06-06): Collapse/Expand-Logik aus
// blade_stack_controller.js ausgelagert (Refactoring-Schritt 4). Das
// Doppelklick-Collapse/Expand eines Blades inkl. der sticky-/transition-
// sensiblen Layout-Choreografie. Wird als Mixin aufs Prototype gemixt
// (Stimulus findet `blade-stack#toggleCollapse` über die Prototype-Chain),
// `this`-gebunden, reines Code-Move — KEIN Verhalten geändert.
//
// Enthaltene Methoden:
//   toggleCollapse           — data-action, Doppelklick auf Spine collapse/expand
//   _onCollapseTransitionEnd — einmaliger width-transitionend-Listener (+ Fallback)
//   _expandCard              — sicherstellen, dass eine Card nicht collapsed ist
//   _autoCollapseSourceList  — No-Op-Stub (#224), Call-Sites bleiben unverändert

export const BladeStackCollapseMixin = {
  toggleCollapse(event) {
    // #474 (Hans, 2026-06-02): Collapse ist eine Desktop-Funktion. Mobil
    // uebernimmt der Doppel-Tap auf einen Spine die Sprung-Navigation
    // (_onSpineTouchEnd); ein evtl. synthetisiertes `dblclick` darf hier
    // NICHT collapsen. Die Tastatur-Collapse-Shortcuts laufen nur am
    // Desktop und sind davon nicht betroffen.
    if (!this._isDesktop()) return
    // #224 (2026-05-19): preventDefault, sonst selektiert der Browser
    // beim Doppelklick auf den Spine den Text drumherum (und nach
    // Expand-Animation sieht das aus, als waere der ganze Body
    // markiert). Plus: existierende Selektion explizit aufheben.
    event.preventDefault()
    window.getSelection?.()?.removeAllRanges?.()
    const card = event.currentTarget.closest(".stack-card")
    if (!card) return
    const collapsed = card.dataset.collapsed === "true"
    // #224 (2026-05-19, Hans): beim Collapsen den Spine an seiner
    // visuellen Position halten — sonst rutscht er weg, wenn rechts
    // davon Blades aufschliessen und ein zweites Doppelklick-Toggle
    // ohne Mausbewegung nicht mehr trifft. Vor dem restickify die
    // Spine-Screen-Position merken, nachher per scrollLeft-Korrektur
    // ausgleichen. Beim Expanden weiter scrollen wie bisher.
    // #277 follow-up: nur beim COLLAPSEN den Breiten-Cache pre-flippen.
    // Sonst macht der forced reflow in restickify die Breiten-Transition
    // fuer die kollabierende Card kaputt (commitet den Endwert ins
    // Layout bevor die CSS-Transition startet). Beim EXPANDEN funktioniert
    // restickify ohne Hint, weil der getBCR-Wert dort die alte Breite
    // (28px) zurueckliefert und damit korrekt waere bzw. die Sticky-
    // Position auf das End-Layout angepasst werden muss.
    // #277 v4: VOLLSTAENDIG defer alle Layout-Reads + restickify auf
    // transitionend. Die toggleCollapse-Funktion macht synchron NUR
    // den dataset-Flip — keine getBCR-Aufrufe, keine restickify-
    // Schreibvorgaenge. Damit kann die CSS-Breiten-Transition
    // ungestoert starten. Nach Abschluss (transitionend) korrigieren
    // wir Sticky-Positionen + ggf. scrollLeft fuer die Spine-Position.
    const beforeLeft = collapsed ? null : card.getBoundingClientRect().left
    // #277 v6: beim COLLAPSEN den inneren Body per flex:0 0 <px>
    // einfrieren, BEVOR die Card-Breite animiert. Sonst zwingt der
    // flex-1 / min-w-0 den Body waehrend der Width-Transition auf
    // 0px Breite — Text bricht auf 1 Zeichen pro Zeile um und ist
    // kurz als „schmaler Streifen Text" sichtbar (Hans-Report).
    // Mit dem freeze behaelt der Body seine alte Layout-Breite,
    // overflow:hidden auf der Card schneidet ihn rechts ab.
    // Beim EXPANDEN den Freeze wieder aufheben, sobald der Flip done ist.
    // #277 v7: zusaetzlich inline `max-width` auf die aktuelle Pixel-
    // breite setzen, BEVOR data-collapsed flippt. Ursache des „instant
    // collapse"-Effekts: die CSS-Regel `max-width: 1.75rem !important`
    // im collapsed-State wuerde von der inline `max-width: none` aus
    // transitionieren — `none` ist nicht interpolierbar, also snapped
    // max-width zu 28px und CLAMPT die gerenderte Breite sofort,
    // obwohl `width` selbst sauber animiert. Mit einem finiten
    // inline-Startwert kann max-width genauso 576 → 28 transition'en
    // wie width, und die Card glides sichtbar zu.
    if (!collapsed) {
      const cw = Math.round(card.getBoundingClientRect().width)
      card.style.maxWidth = cw + "px"
      const body = card.querySelector(":scope > .overflow-y-auto")
      if (body) {
        const bw = Math.round(body.getBoundingClientRect().width)
        body.style.flex = `0 0 ${bw}px`
      }
    }
    card.dataset.collapsed = collapsed ? "false" : "true"
    if (collapsed) {
      // Expand — nach Transition Card in den Viewport scrollen,
      // Body-Flex-Freeze aufheben, inline max-width loeschen (damit
      // spaeteres Resize ueber 576px wieder moeglich ist).
      const body = card.querySelector(":scope > .overflow-y-auto")
      if (body) body.style.flex = ""
      this._onCollapseTransitionEnd(card, () => {
        card.style.maxWidth = ""
        this.restickify()
        card.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" })
      })
    } else if (beforeLeft != null) {
      this._onCollapseTransitionEnd(card, () => {
        this.restickify()
        const afterLeft = card.getBoundingClientRect().left
        const shift = afterLeft - beforeLeft
        if (shift !== 0) {
          this.containerTarget.scrollTo({
            left: this.containerTarget.scrollLeft + shift, behavior: "smooth"
          })
        }
      })
    }
  },

  // #277 v4: einmaliger transitionend-Listener auf der Card, gefiltert
  // auf die width-Property. Fallback-Timeout, falls der event-Pfad
  // unzuverlaessig ist (z.B. unterbrochene Transition).
  _onCollapseTransitionEnd(card, cb) {
    let fired = false
    const fire = () => { if (fired) return; fired = true; cb() }
    const handler = (e) => { if (e.propertyName === "width") { card.removeEventListener("transitionend", handler); fire() } }
    card.addEventListener("transitionend", handler)
    setTimeout(fire, 280)  // Fallback ~ Transition + Slack
  },

  // Hilfsfunktion: stelle sicher, dass die Card NICHT collapsed ist.
  // Wird vor Focus-Scroll auf eine existierende Card aufgerufen, damit
  // ein fokussiertes Item sicher sichtbar ist.
  _expandCard(card) {
    if (card.dataset.collapsed === "true") {
      card.dataset.collapsed = "false"
      this.restickify()
    }
  },

  // #224 (#391): Auto-Collapse von Listen-Blades nach Item-Auswahl
  // entfaellt — Hans's neue Spec sagt explizit „kein automatisches
  // Autocollapse von Listenblades. Das hat sich aus verwirrend
  // herausgestellt." Methode bleibt als No-Op stehen, damit die
  // Call-Sites nicht alle angepasst werden muessen.
  _autoCollapseSourceList(_event) { /* no-op since #224 */ }
}
