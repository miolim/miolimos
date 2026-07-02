import { Controller } from "@hotwired/stimulus"

// #352 (Hans, 2026-05-25): Bulk-Toggle fuer Heading- bzw. Content-
// Knoten im Rendering-Blade. Klick faltet alle Knoten der jeweiligen
// Rolle auf oder zu (Flip auf Basis des MEHRHEITSZUSTANDS — wenn die
// meisten zu sind, alle auf; sonst alle zu).
//
// Wir manipulieren `data-render-node-open-value` und ziehen via
// .render-node-Controller#openValueChanged automatisch die UI
// hinterher. Falls keine render-node-Instanz an dem Knoten haengt
// (= can_toggle war false, kein Body), ueberspringen wir.
export default class extends Controller {
  static targets = ["iconHeading", "iconContent"]

  toggleAllHeadings() { this._toggleRole("heading", this.iconHeadingTarget) }
  toggleAllContent()  { this._toggleRole("content", this.iconContentTarget) }

  _toggleRole(role, iconEl) {
    const sections = Array.from(this.element.querySelectorAll(
      `[data-controller~="render-node"][data-role="${role}"]`
    ))
    if (sections.length === 0) return

    // Mehrheits-State bestimmen: wenn >= Haelfte offen, dann zumachen,
    // sonst aufmachen.
    const openCount = sections.filter(s => s.dataset.renderNodeOpenValue === "true").length
    const shouldOpen = openCount * 2 < sections.length

    sections.forEach(s => {
      s.dataset.renderNodeOpenValue = shouldOpen ? "true" : "false"
      const ctrl = this.application.getControllerForElementAndIdentifier(s, "render-node")
      // openValue-Change triggert apply() im Stimulus-Lifecycle; falls
      // der Controller noch nicht connected ist (Race), rufen wir's
      // optimistisch an.
      ctrl?.apply?.()
    })

    if (iconEl) iconEl.classList.toggle("rotate-90", shouldOpen)
  }
}
