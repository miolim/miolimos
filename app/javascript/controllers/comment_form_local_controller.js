import { Controller } from "@hotwired/stimulus"

// #324 (Hans, 2026-05-24): Mehrfach-Instanzen einer Card brechen
// Turbo's getElementById — alle Streams landen in der ERSTEN Card im
// DOM (nicht in der getippten). Wir fangen das Submit ab, holen die
// Turbo-Stream-Antwort selbst und wenden sie LOKAL im naechstgelegenen
// .stack-card-Vorfahren an. Bei `replace` greift der Lookup wahlweise
// auf das Element MIT der gleichen ID innerhalb der Card oder, wenn
// nichts da, global (z.B. fuer toast_stack-Append).
export default class extends Controller {
  async submit(event) {
    event.preventDefault()
    const form = this.element
    const data = new FormData(form)

    // Submit-Button-Identitaet (z.B. as_draft=1 vs Default-Submit) muss
    // explizit mitgeschickt werden — FormData ignoriert den Klick-
    // Submitter.
    const submitter = event.submitter
    if (submitter && submitter.name && !data.has(submitter.name)) {
      data.append(submitter.name, submitter.value || "")
    }

    // #340 (Hans, 2026-05-24): kommentar-autosave-controller listened
    // auf `turbo:submit-start`, NICHT `turbo:submit-end`, um sich
    // `submitted=true` zu merken. Wir intercept-en das normale Turbo-
    // Submit, also feuern wir das Event manuell BEVOR die Fetch laeuft,
    // damit ein spaeterer disconnect-Beacon kein Zweit-Save absetzt.
    form.dispatchEvent(new CustomEvent("turbo:submit-start", {
      bubbles: true, detail: {}
    }))

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    let res
    try {
      res = await fetch(form.action, {
        method: (form.method || "POST").toUpperCase(),
        body: data,
        headers: {
          "Accept":       "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrf
        }
      })
    } catch (err) {
      console.warn("comment-form-local: fetch failed", err)
      return
    }
    if (!res.ok) {
      console.warn("comment-form-local: server error", res.status)
      return
    }
    const html = await res.text()
    this._applyStreams(html)
    // submit-end ein letztes Mal feuern, damit andere Stimulus-
    // Controller (z.B. quick-create#_onSubmitEnd, falls die Karte in
    // einem Quick-Create-Slot sitzt) die Erfolgsmeldung sehen.
    form.dispatchEvent(new CustomEvent("turbo:submit-end", {
      bubbles: true, detail: { success: true }
    }))
  }

  _applyStreams(html) {
    const scope = this.element.closest(".stack-card") || document
    const tpl = document.createElement("template")
    tpl.innerHTML = html.trim()
    tpl.content.querySelectorAll("turbo-stream").forEach(stream => {
      const action = stream.getAttribute("action")
      const targetId = stream.getAttribute("target")
      if (!action || !targetId) return
      // Erst im Card-Scope suchen, dann global (fuer Toast etc.).
      const localTarget = scope.querySelector?.(`#${CSS.escape(targetId)}`)
      const targetEl = localTarget || document.getElementById(targetId)
      if (!targetEl) return
      const innerTpl = stream.querySelector("template")
      const content  = innerTpl ? innerTpl.content : null
      switch (action) {
        case "append":
          if (content) targetEl.appendChild(content.cloneNode(true))
          break
        case "prepend":
          if (content) targetEl.insertBefore(content.cloneNode(true), targetEl.firstChild)
          break
        case "replace":
          if (content) targetEl.replaceWith(content.cloneNode(true))
          break
        case "update":
          if (content) {
            targetEl.innerHTML = ""
            targetEl.appendChild(content.cloneNode(true))
          }
          break
        case "remove":
          targetEl.remove()
          break
      }
    })
  }
}
