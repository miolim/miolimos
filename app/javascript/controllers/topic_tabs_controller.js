import { Controller } from "@hotwired/stimulus"

// #253 follow-up: Tab-Wechsel innerhalb einer Topic-List-Blade.
//
// Bisher war jeder Tab-Link eine Full-Page-Navigation auf
// /topics/:slug?tab=X (turbo_frame:_top). Wenn die Topic-List-Blade
// aber als Card in einem groesseren Stack liegt (Sidebar-Plus /
// Subtopic-Klick), zerstoert die Navigation den ganzen Stack und
// baut einen neuen mit nur dieser Card.
//
// Stattdessen: list_card?tab=X fetchen und die <article>-Card an Ort
// und Stelle ersetzen. Der blade-stack-MutationObserver kuemmert sich
// danach um restickify/Highlight.
export default class extends Controller {
  // event.params.url kommt aus data-topic-tabs-url-param am Link.
  async switch(event) {
    event.preventDefault()
    const url  = event.params.url
    const card = this.element.closest(".stack-card")
    if (!url || !card) return
    try {
      const res = await fetch(url, { headers: { "Accept": "text/html" } })
      if (!res.ok) { this._toastError(window.t("topic_tabs.tab_load_failed", { status: res.status })); return }
      const html = await res.text()
      const tpl  = document.createElement("template")
      tpl.innerHTML = html.trim()
      const fresh = tpl.content.firstElementChild
      if (fresh) {
        // #484 (Hans, 2026-06-03): gespeicherte Breite der alten Karte auf
        // die frische uebernehmen, BEVOR sie ins DOM kommt — sonst rendert
        // sie kurz auf der CSS-Default-Breite (w-[60rem]) und springt dann
        // (restickify setzt style.width erst nach dem Insert).
        if (card.style.width) fresh.style.width = card.style.width
        if (card.style.flex)  fresh.style.flex  = card.style.flex
        card.replaceWith(fresh)
        this._syncStack(fresh)
      }
    } catch (err) {
      console.warn("topic-tabs error", err)
      this._toastError(window.t("topic_tabs.tab_load_failed_network"))
    }
  }

  // #637: Fehler sichtbar machen — console.warn allein liest niemand
  // („Register lässt sich nicht aufrufen" ohne jede Rückmeldung).
  _toastError(message) {
    const stack = document.getElementById("toast_stack")
    if (!stack) return
    const div = document.createElement("div")
    div.setAttribute("data-controller", "toast")
    div.className = "flex items-center gap-3 bg-rose-700 text-white text-sm px-3 py-2 rounded shadow-lg"
    div.innerHTML = `<span class="flex-1 min-w-0"></span>
      <button type="button" data-action="click->toast#dismiss"
              class="text-rose-200 hover:text-white text-lg leading-none">×</button>`
    div.querySelector("span").textContent = message
    stack.appendChild(div)
  }

  // #597: Nach dem Card-Replace Trail + ?stack=-URL nachziehen — die
  // data-uuid ändert sich beim Tab-Wechsel (Tab-Suffix), und ohne Sync
  // restaurierte ein Browser-Refresh den ALTEN Stack-Zustand (Hans sah
  // statt des frisch geöffneten Topics eine Dublette eines älteren).
  _syncStack(fresh) {
    const stackEl = fresh.closest('[data-controller~="blade-stack"]')
    const stack = window.Stimulus?.getControllerForElementAndIdentifier(stackEl, "blade-stack")
    stack?.pushTrailState()
  }

  // #484 (Hans, 2026-06-03): GET-Formular (Listen-Toolbar) IN PLACE laden,
  // statt Full-Page-Navigation — verhindert neuen Stack + Breiten-Flimmern.
  // Das Formular zeigt auf list_card; URL aus action + Feldern (inkl.
  // geklicktem Submit-Button) bauen und die Karte wie bei #switch ersetzen.
  async switchForm(event) {
    event.preventDefault()
    const form = event.target
    const card = this.element.closest(".stack-card")
    if (!form || !card) return
    const url = new URL(form.action, window.location.origin)
    const fd  = new FormData(form)
    if (event.submitter && event.submitter.name) {
      fd.append(event.submitter.name, event.submitter.value)
    }
    for (const [k, v] of fd) url.searchParams.set(k, v)
    try {
      const res = await fetch(url.toString(), { headers: { "Accept": "text/html" } })
      if (!res.ok) { this._toastError(window.t("topic_tabs.list_load_failed", { status: res.status })); return }
      const html = await res.text()
      const tpl  = document.createElement("template")
      tpl.innerHTML = html.trim()
      const fresh = tpl.content.firstElementChild
      if (fresh) {
        // #484 (Hans, 2026-06-03): gespeicherte Breite der alten Karte auf
        // die frische uebernehmen, BEVOR sie ins DOM kommt — sonst rendert
        // sie kurz auf der CSS-Default-Breite (w-[60rem]) und springt dann
        // (restickify setzt style.width erst nach dem Insert).
        if (card.style.width) fresh.style.width = card.style.width
        if (card.style.flex)  fresh.style.flex  = card.style.flex
        card.replaceWith(fresh)
        this._syncStack(fresh)
      }
    } catch (err) {
      console.warn("topic-tabs switchForm error", err)
    }
  }
}
