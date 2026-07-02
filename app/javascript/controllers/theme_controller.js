import { Controller } from "@hotwired/stimulus"

// #772 (Hans, 2026-06-27): Dark-Mode-Umschalter in der Topbar. Quelle der
// Wahrheit ist ein Cookie `theme`, das der Server beim Rendern in die
// `dark`-Klasse auf <html> übersetzt — so überlebt der Modus auch Turbo-
// Morph-Refreshes (die <html> neu rendern) und es gibt kein FOUC. Der Klick
// setzt das Cookie und spiegelt die Klasse sofort fürs aktuelle Dokument.
export default class extends Controller {
  toggle() {
    const dark = !document.documentElement.classList.contains("dark")
    document.documentElement.classList.toggle("dark", dark)
    document.cookie = `theme=${dark ? "dark" : "light"}; path=/; max-age=31536000; samesite=lax`
    this.element.setAttribute("aria-pressed", dark ? "true" : "false")
  }
}
