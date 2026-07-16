import { Controller } from "@hotwired/stimulus"

// #1027: „E-Mail verfassen" — baut aus An/Betreff/Text eine Compose-URL
// und öffnet sie. Strategie kommt aus der Nutzer-Vorliebe (Server-seitig
// aufgelöst): "gmail" = Gmail-Compose im Browser, "mailto" = Standard-
// Mail-Client. Lange mailto-Bodies sprengen die URL-Länge mancher
// Clients — ab MAILTO_LIMIT wandert der Text stattdessen in die
// Zwischenablage und der Entwurf öffnet ohne Body.
export default class extends Controller {
  static targets = ["to", "subject", "body"]
  static values  = { strategy: { type: String, default: "mailto" } }

  MAILTO_LIMIT = 1800

  async open(event) {
    event.preventDefault()
    const to      = this.toTarget.value.trim()
    const subject = this.subjectTarget.value.trim()
    const body    = this.bodyTarget.value
    if (!to) { this.toTarget.focus(); return }

    if (this.strategyValue === "gmail") {
      const p = new URLSearchParams({ view: "cm", fs: "1", to: to })
      if (subject) p.set("su", subject)
      if (body)    p.set("body", body)
      window.open(`https://mail.google.com/mail/?${p.toString()}`, "_blank", "noopener")
      return
    }

    let url = this.mailtoUrl(to, subject, body)
    if (body && url.length > this.MAILTO_LIMIT) {
      await this.copyToClipboard(body, window.t("mail_compose.copied_overflow"))
      url = this.mailtoUrl(to, subject, "")
    }
    window.location.href = url
  }

  // Nur den Text kopieren (explizite Zwischenablage-Variante).
  async copyBody(event) {
    event.preventDefault()
    if (!this.bodyTarget.value) return
    await this.copyToClipboard(this.bodyTarget.value, window.t("mail_compose.copied"))
  }

  mailtoUrl(to, subject, body) {
    const q = []
    if (subject) q.push(`subject=${encodeURIComponent(subject)}`)
    if (body)    q.push(`body=${encodeURIComponent(body)}`)
    return `mailto:${encodeURIComponent(to)}${q.length ? `?${q.join("&")}` : ""}`
  }

  async copyToClipboard(text, toast) {
    try {
      await navigator.clipboard.writeText(text)
      this.flashToast(toast)
    } catch (err) {
      console.warn("clipboard copy failed:", err)
      this.flashToast(window.t("copy.copy_failed"))
    }
  }

  // Gleiche Toast-Mechanik wie copy_clipboard_controller.
  flashToast(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.setAttribute("data-action", "mouseenter->toast#pause mouseleave->toast#resume")
    div.className = "flex items-center gap-3 bg-slate-900 text-white text-sm px-3 py-2 rounded shadow-lg"
    div.innerHTML = `<span class="flex-1 min-w-0">${message}</span>
      <button type="button" data-action="click->toast#dismiss"
              class="text-slate-400 hover:text-white text-lg leading-none">×</button>`
    stack.appendChild(div)
  }
}
