import { Controller } from "@hotwired/stimulus"

// #160 Phase 2: Trackt Sichtzeit einer Entität für die User-History.
// Wird auf den Detail-Partials der trackbaren Entitäten gemountet
// (Task / KnowledgeItem / Source / Awaiting / Topic). Workflow:
//
//   connect()                — Timer setzen, viewStartedAt merken.
//   nach `thresholdValue` ms — erstmaliger POST mit duration_ms.
//                              Antwort enthält view-id; wird als
//                              `lastViewId` gemerkt, damit Folge-
//                              Pings dieselbe Server-Row updaten.
//   visibilitychange         — pausiert Akkumulation bei Tab-weg,
//                              resumed bei Tab-zurück.
//   markEdited()             — public API: setze was_edited=true beim
//                              nächsten Ping. Wird von edit-Form-
//                              Submit-Hooks (Phase 4) aufgerufen.
//   disconnect()             — finaler POST via navigator.sendBeacon
//                              mit aufakkumulierter Dauer.
//
// Markup:
//   <div data-controller="view-tracker"
//        data-view-tracker-viewable-type-value="Task"
//        data-view-tracker-viewable-id-value="42">
export default class extends Controller {
  static values = {
    viewableType: String,
    // KnowledgeItem hat eine UUID-PK statt Bigint — daher String.
    viewableId:   String,
    threshold:    { type: Number, default: 3000 } // Mindest-Dauer für Aufnahme (ms)
  }

  connect() {
    // Sanity: nur tracken, wenn Type und ID gesetzt sind. Sonst
    // (z.B. unset-Defaults im Partial) Controller still rauslassen.
    if (!this.viewableTypeValue || !this.viewableIdValue) return

    this.sessionToken = this.ensureSessionToken()
    this.accumulatedMs = 0
    this.wasEdited = false
    this.lastViewId = null
    this.tracking = true

    // #816: Im Blade-Stack zählt NUR die aktive (fokussierte) Card —
    // vorher akkumulierten ALLE offenen Cards gleichzeitig Sichtzeit,
    // und schon das Aufräumen eines Stacks erzeugte Verlaufs-Einträge.
    // Der Active-State lebt als data-active auf der .stack-card
    // (setActiveCard); wir beobachten ihn per MutationObserver.
    // Außerhalb eines Stacks (Vollansicht) gilt wie bisher: sichtbar = zählt.
    this.card = this.element.closest(".stack-card")
    if (this.card) {
      this.activeObserver = new MutationObserver(() => this.onGateChange())
      this.activeObserver.observe(this.card, { attributes: true, attributeFilter: ["data-active"] })
    }
    this.segmentStart = this.isCounting() ? performance.now() : null

    // Boundary-Listener für Tab-Wechsel und Page-Unload. Diese werden
    // im disconnect() wieder entfernt, damit alte Detail-Partials nach
    // Turbo-Replace keine Ghost-Listener hinterlassen.
    this.onVisibility = this.onVisibility.bind(this)
    this.onBeforeUnload = this.onBeforeUnload.bind(this)
    this.onSubmitEnd = this.onSubmitEnd.bind(this)
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("beforeunload", this.onBeforeUnload)
    // Phase 4: jede erfolgreiche Turbo-Submission innerhalb dieses
    // Detail-Partials zählt als Edit. Listener am document, weil
    // Turbo das Event dort dispatcht und unsere Subtree-Prüfung im
    // Handler den Scope macht.
    document.addEventListener("turbo:submit-end", this.onSubmitEnd)

    // Erstmaliger POST, sobald `threshold` ms Fokus-Sichtzeit erreicht
    // sind. Re-armt sich bei Fokus-/Tab-Wechseln (#816 — vorher stand
    // „später nochmal versuchen" nur im Kommentar).
    this.pinged = false
    this.armPingTimer()
  }

  disconnect() {
    if (!this.tracking) return
    this.tracking = false
    if (this.thresholdTimer) clearTimeout(this.thresholdTimer)
    if (this.activeObserver) this.activeObserver.disconnect()
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    document.removeEventListener("turbo:submit-end", this.onSubmitEnd)

    // Final ping: nur, wenn wir schon die Threshold überschritten haben
    // (sonst war's nur ein flüchtiger Klick). Verwendet sendBeacon, um
    // beim Turbo-Frame-Replace nicht eine Promise zu verlieren.
    const total = this.totalMs()
    if (total >= this.thresholdValue) this.sendBeacon(total)
  }

  // Public API für Phase 4: markiert die laufende View als "bearbeitet".
  markEdited() {
    this.wasEdited = true
  }

  // Phase 4: Hook auf Turbo-Form-Submits. Wenn das eingereichte
  // <form> innerhalb dieses Detail-Partials liegt UND der Submit
  // erfolgreich war, markieren wir die View als bearbeitet.
  onSubmitEnd(event) {
    if (!event.detail?.success) return
    const form = event.target
    if (!form || !this.element.contains(form)) return
    this.markEdited()
  }

  // ─── interne Methoden ────────────────────────────────────────────

  onVisibility() { this.onGateChange() }

  // Zählt gerade? Tab sichtbar UND (keine Stack-Card ODER diese ist aktiv).
  isCounting() {
    if (document.visibilityState === "hidden") return false
    if (this.card && this.card.dataset.active !== "true") return false
    return true
  }

  // Gemeinsame Reaktion auf Tab-Sichtbarkeit UND Fokus-Wechsel (#816):
  // Segment einfrieren bzw. neu starten, Ping-Timer nachziehen.
  onGateChange() {
    if (this.isCounting()) {
      if (this.segmentStart === null) this.segmentStart = performance.now()
      this.armPingTimer()
    } else {
      if (this.segmentStart !== null) {
        this.accumulatedMs += performance.now() - this.segmentStart
        this.segmentStart = null
      }
      if (this.thresholdTimer) { clearTimeout(this.thresholdTimer); this.thresholdTimer = null }
    }
  }

  // Timer bis zum Erreichen der Threshold-Restzeit — nur wenn gerade
  // gezählt wird und noch kein Erst-Ping raus ist.
  armPingTimer() {
    if (!this.tracking || this.pinged) return
    if (this.thresholdTimer) clearTimeout(this.thresholdTimer)
    if (!this.isCounting()) { this.thresholdTimer = null; return }
    const remaining = Math.max(0, this.thresholdValue - this.totalMs())
    this.thresholdTimer = setTimeout(() => this.firstPing(), remaining)
  }

  onBeforeUnload() {
    if (!this.tracking) return
    const total = this.totalMs()
    if (total >= this.thresholdValue) this.sendBeacon(total)
  }

  totalMs() {
    const live = this.segmentStart !== null ? (performance.now() - this.segmentStart) : 0
    return Math.round(this.accumulatedMs + live)
  }

  async firstPing() {
    if (!this.tracking || this.pinged) return
    const total = this.totalMs()
    if (total < this.thresholdValue) { this.armPingTimer(); return }
    this.pinged = true
    try {
      const res = await fetch("/actor_views", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        body: new URLSearchParams({
          viewable_type: this.viewableTypeValue,
          viewable_id:   String(this.viewableIdValue),
          duration_ms:   String(total),
          was_edited:    String(this.wasEdited),
          session_token: this.sessionToken
        }).toString(),
        credentials: "same-origin"
      })
      if (res.ok) {
        const json = await res.json()
        this.lastViewId = json.id
      }
    } catch (e) {
      // Tracker-Fehler dürfen die UX nicht stören.
      console.debug("view-tracker firstPing failed:", e)
    }
  }

  sendBeacon(total) {
    if (!navigator.sendBeacon) return
    const data = new URLSearchParams({
      viewable_type: this.viewableTypeValue,
      viewable_id:   String(this.viewableIdValue),
      duration_ms:   String(total),
      was_edited:    String(this.wasEdited),
      session_token: this.sessionToken
    })
    // sendBeacon nutzt automatisch den vom Browser geöffneten Channel;
    // Cookies/Session werden mitgeschickt. Form-encoded reicht für
    // unser Endpoint.
    navigator.sendBeacon(
      "/actor_views",
      new Blob([data.toString()], { type: "application/x-www-form-urlencoded" })
    )
  }

  // sessionStorage-basierter Token (1 pro Browser-Session). Anonyme
  // Random-ID, kein PII. Erlaubt späteren parallele-Sitzungen-Filter
  // auf der History-Page (#160 Default 4).
  ensureSessionToken() {
    let t = sessionStorage.getItem("view-tracker.session")
    if (!t) {
      t = (crypto?.randomUUID?.() || String(Date.now()) + Math.random().toString(16).slice(2))
      sessionStorage.setItem("view-tracker.session", t)
    }
    return t
  }
}
