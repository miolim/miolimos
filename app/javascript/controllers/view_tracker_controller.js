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
    this.segmentStart = (document.visibilityState === "hidden") ? null : performance.now()
    this.wasEdited = false
    this.lastViewId = null
    this.tracking = true

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

    // Erstmaliger POST nach `threshold` ms — falls die Entity da noch
    // sichtbar ist.
    this.thresholdTimer = setTimeout(() => this.firstPing(), this.thresholdValue)
  }

  disconnect() {
    if (!this.tracking) return
    this.tracking = false
    if (this.thresholdTimer) clearTimeout(this.thresholdTimer)
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

  onVisibility() {
    if (document.visibilityState === "hidden") {
      // Tab wird verlassen — laufendes Segment einfrieren.
      if (this.segmentStart !== null) {
        this.accumulatedMs += performance.now() - this.segmentStart
        this.segmentStart = null
      }
    } else {
      // Tab kommt zurück — neues Segment beginnt.
      if (this.segmentStart === null) this.segmentStart = performance.now()
    }
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
    if (!this.tracking) return
    const total = this.totalMs()
    if (total < this.thresholdValue) return  // Tab war versteckt → später nochmal versuchen
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
