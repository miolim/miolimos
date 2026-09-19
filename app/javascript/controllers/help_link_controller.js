import BladeLinkController from "controllers/blade_link_controller"
import { offenerReiter, hilfeSchluessel } from "lib/help_tab"

// immoOS #1658 Stufe 2 (Hans): Das Fragezeichen im Card-Rücken öffnet die Hilfe
// zum GERADE OFFENEN REITER, nicht nur die zur Karte.
//
// Welcher Reiter offen ist, weiß nur der Browser (simple-tabs schaltet die
// Panels clientseitig). Deshalb hängt erst der Klick den Reiternamen an den
// Schlüssel: `property` → `property.settlement`. Findet sich kein Reiter (Card
// ohne Reiter), bleibt es beim Schlüssel der Karte.
export default class extends BladeLinkController {
  append(event) {
    const card = event.currentTarget?.closest("article.stack-card")
    this.idValue = hilfeSchluessel(this.idValue, offenerReiter(card))
    return super.append(event)
  }
}
