import { Controller } from "@hotwired/stimulus"
import { isAutosaveTrigger, fieldDescriptor, refindField, darfWertZurueck } from "lib/autosave_feedback"

// #1496 (aus immoos #1457 uebernommen). Hans dort: „Nach der Eingabe/Auswahl eines Feldes … wird das Feld
// gespeichert … Wenn man in der Zwischenzeit bereits zum nächsten Feld gegangen
// ist, verliert das Feld wieder den Fokus und man muss es erneut auswählen …
// Bei Datumsfeldern muss man jedes Mal neu klicken, um dann den Monat und
// schließlich das Jahr einzugeben."
//
// Zwei Ursachen, zwei Antworten — beide hier, weil beide vom BEDIENGEFÜHL
// handeln und nicht vom Speichern selbst:
//
//   1. ZU BREITE ANTWORT. Ein Feld-Save lässt den Server oft die ganze Card
//      neu rendern; damit werden ALLE Felder ausgetauscht, auch das, in dem
//      gerade getippt wird. Einem gelöschten Knoten gibt der Browser keinen
//      Fokus zurück. Hier wird deshalb vor dem Austausch gemerkt, WO der
//      Cursor steht, und danach dorthin zurückgekehrt — an das Feld, das der
//      Nutzer gerade bearbeitet, nicht an das gespeicherte.
//
//   2. ZU FRÜHER AUSLÖSER bei Datumsfeldern. `type="date"` meldet `change`,
//      sobald ein VOLLSTÄNDIGES Datum dasteht — beim Ändern des Tages ist es
//      das sofort wieder, und mitten in der Eingabe wird gespeichert. Solche
//      Felder speichern deshalb erst beim Verlassen, und nur wenn sich der
//      Wert wirklich geändert hat.
//
// Beides greift dokumentweit an den vorhandenen Autosave-Feldern (bei uns 77), ohne
// eine einzige Ansicht anzufassen — erkannt am Inline-Handler, wie bei der
// Rückmeldung von #1114.
export default class extends Controller {
  static EINGABEFELDER = ["INPUT", "SELECT", "TEXTAREA"]

  connect() {
    this._merk = null

    // ── 1. Fokus über den Austausch retten ──────────────────────────────
    // Gemerkt wird VOR dem Austausch, hergestellt DANACH. Ein
    // `requestAnimationFrame` nach dem before-Event genügt nicht: Da steht das
    // alte DOM noch, der Cursor sitzt noch im alten Knoten — und der Schutz
    // „der Nutzer ist schon weiter" würde fälschlich greifen. Gemessen an der
    // Card aus #1457.
    this._vorRender = () => this._merken()
    this._nachRender = () => this._herstellen()
    document.addEventListener("turbo:before-frame-render", this._vorRender)
    document.addEventListener("turbo:frame-render", this._nachRender)
    // Streams kennen kein „danach"-Ereignis je Stream — hier genügt das Ende
    // der laufenden Aufgabe, dann steht das neue DOM.
    this._vorStream = () => { this._merken(); setTimeout(this._nachRender, 0) }
    document.addEventListener("turbo:before-stream-render", this._vorStream)

    // ── 2. Datumsfelder erst beim Verlassen speichern ────────────────────
    // Capture am Dokument: `stopImmediatePropagation` hält das Event vom Ziel
    // fern, damit der Inline-Handler (`onchange="this.form.requestSubmit()"`)
    // nicht anspringt. Nur solange das Feld den Fokus hat — ein Save, der von
    // woanders ausgelöst wird, geht uns nichts an.
    this._fruehesSpeichernBremsen = (e) => {
      const el = e.target
      if (!this._istDatumsAutosave(el) || document.activeElement !== el) return
      e.stopImmediatePropagation()
      el.dataset.autosaveOffen = "1"
    }
    // Beim Verlassen nachholen — aber nur bei echter Änderung. `defaultValue`
    // ist der Wert, mit dem der Server das Feld gerendert hat.
    this._beimVerlassen = (e) => {
      const el = e.target
      if (!el?.dataset?.autosaveOffen) return
      delete el.dataset.autosaveOffen
      if (el.value !== el.defaultValue) el.form?.requestSubmit()
    }
    document.addEventListener("change", this._fruehesSpeichernBremsen, true)
    document.addEventListener("focusout", this._beimVerlassen, true)
  }

  disconnect() {
    document.removeEventListener("turbo:before-frame-render", this._vorRender)
    document.removeEventListener("turbo:frame-render", this._nachRender)
    document.removeEventListener("turbo:before-stream-render", this._vorStream)
    document.removeEventListener("change", this._fruehesSpeichernBremsen, true)
    document.removeEventListener("focusout", this._beimVerlassen, true)
  }

  _istDatumsAutosave(el) {
    return el?.tagName === "INPUT" && el.type === "date" && isAutosaveTrigger(el)
  }

  _merken() {
    const el = document.activeElement
    if (!el || !el.form || !this.constructor.EINGABEFELDER.includes(el.tagName)) return

    // Die Cursorposition gibt es nur bei Textfeldern; date/number/select
    // werfen beim Zugriff bzw. liefern nichts Brauchbares.
    let start = null
    let ende = null
    try {
      start = el.selectionStart
      ende = el.selectionEnd
    } catch { /* Feldart ohne Auswahlbereich */ }

    // #1457 R2 (Fork): Auch den WERT merken — der Ort allein genügt nicht. Dazu den
    // Wert, mit dem der Server das Feld gerendert hat (`defaultValue`): Nur an
    // ihm ist später erkennbar, ob der Server das Feld selbst geändert hat.
    this._merk = {
      desc: fieldDescriptor(el.form, el), start, ende,
      wert: typeof el.value === "string" ? el.value : null,
      geliefert: typeof el.defaultValue === "string" ? el.defaultValue : null
    }
  }

  _herstellen() {
    const merk = this._merk
    this._merk = null
    if (!merk) return

    // Steht der Cursor schon wieder in einem Feld, hat der Nutzer selbst
    // weitergeklickt — dann nichts anfassen.
    // `isConnected` ist hier der Kern: Nach dem Austausch zeigt activeElement
    // teils noch auf den herausgelösten Knoten — der beweist nichts.
    const jetzt = document.activeElement
    if (jetzt?.isConnected && jetzt !== document.body && jetzt.form) return

    const feld = refindField(document, merk.desc)
    if (!feld || feld === jetzt) return

    feld.focus()
    // #1457 R2 (Fork): Der Wert VOR der Cursorposition — sonst klemmt der Browser den
    // Cursor auf die Länge des kürzeren Serverwerts und man landet mitten im
    // Wort statt dahinter.
    if (darfWertZurueck(feld, merk)) feld.value = merk.wert
    if (merk.start != null && typeof feld.setSelectionRange === "function") {
      try { feld.setSelectionRange(merk.start, merk.ende) } catch { /* nicht setzbar */ }
    }
  }
}
