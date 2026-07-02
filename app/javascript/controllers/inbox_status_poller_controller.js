import { Controller } from "@hotwired/stimulus"

// Pollt einen Endpoint und übergibt eine ggf. zurückgelieferte
// Turbo-Stream-Antwort an Turbo. Sobald der Server etwas liefert (z.B.
// Frame-Replace und Toast-Append), ist das DOM-Element ersetzt und
// dieser Controller wird automatisch disconnected — kein manuelles
// Stop nötig.
//
// Server-Vertrag:
//   - 204 No Content → weiter pollen
//   - 200 mit Content-Type "text/vnd.turbo-stream.html" → Streams ausführen
//
// Markup:
//   <section data-controller="inbox-status-poller"
//            data-inbox-status-poller-url-value="/inbox/7/poll"
//            data-inbox-status-poller-interval-value="4000">
export default class extends Controller {
  static values = {
    url:      String,
    interval: { type: Number, default: 4000 }
  }

  connect() {
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    if (this.timer) { clearInterval(this.timer); this.timer = null }
  }

  async poll() {
    try {
      const res = await fetch(this.urlValue, {
        headers: { "Accept": "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      if (res.status === 204) return  // immer noch processing
      if (!res.ok) return

      const html = await res.text()
      if (html.trim().length === 0) return

      // Turbo importiert global; wenn nicht verfügbar, harmlos abbrechen.
      if (window.Turbo && window.Turbo.renderStreamMessage) {
        window.Turbo.renderStreamMessage(html)
      }
    } catch (_e) {
      // Netzwerk-Hänger ignorieren — der nächste Poll versucht es erneut.
    }
  }
}
