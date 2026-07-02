// #373 Phase A (Hans, 2026-05-26): CodeMirror-6-Spike fuer den KI-
// Edit-Body. Minimal-Setup: CM6 mit Markdown-Lang-Plugin, ersetzt die
// `<textarea>` visuell — Source bleibt das Textarea-Element (DOM), CM6
// schreibt bei jeder Aenderung zurueck, damit Submit unveraendert
// funktioniert. KEINE Wikilink-/Cite-Decorations in dieser Phase, keine
// Wikilink-Autocomplete-Integration. Aktivierbar per URL-Query
// `?cm6=1`, sonst Verhalten unveraendert.
//
// Markup:
//   <div data-controller="cm6-editor" data-cm6-editor-target="host">
//     <textarea data-cm6-editor-target="textarea">…</textarea>
//   </div>

import { Controller } from "@hotwired/stimulus"
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { markdown } from "@codemirror/lang-markdown"
import { defaultKeymap, history, historyKeymap, indentWithTab, indentMore, indentLess } from "@codemirror/commands"
import { syntaxHighlighting, defaultHighlightStyle, bracketMatching, HighlightStyle } from "@codemirror/language"
import { tags } from "@lezer/highlight"
import { autocompletion, completionKeymap, closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete"
import { miolimDecorations, miolimDecorationTheme } from "lib/cm6_decorations"
import { dispatchBladeShortcut } from "lib/submit_shortcuts"

// #373 Phase C (c) (Hans, 2026-05-26): Slash-Commands fuer schnelles
// Einfuegen von Markdown-Strukturen am Zeilenanfang. Trigger: `/` am
// Anfang einer leeren oder Whitespace-Zeile. Apply ersetzt das `/q`
// (oder was getippt wurde) durch das Snippet.
const SLASH_COMMANDS = [
  { label: "heading1", apply: "# ",   detailKey: "cm6.slash_heading1" },
  { label: "heading2", apply: "## ",  detailKey: "cm6.slash_heading2" },
  { label: "heading3", apply: "### ", detailKey: "cm6.slash_heading3" },
  { label: "quote",    apply: "> ",   detailKey: "cm6.slash_quote" },
  { label: "code",     apply: "```\n\n```", detailKey: "cm6.slash_code",
    moveCursorOffset: 4 },  // hinter `\n`
  { label: "list",     apply: "- ",   detailKey: "cm6.slash_list" },
  { label: "numbered", apply: "1. ",  detailKey: "cm6.slash_numbered" },
  { label: "task",     apply: "- [ ] ", detailKey: "cm6.slash_task" },
  { label: "hr",       apply: "---\n", detailKey: "cm6.slash_hr" },
  { label: "highlight",apply: "==gelb||==", detailKey: "cm6.slash_highlight",
    moveCursorOffset: 5 },  // vor dem `==` am Ende
  { label: "wikilink", apply: "[[]]", detailKey: "cm6.slash_wikilink",
    moveCursorOffset: 2 }
]

function slashCompletion(context) {
  // Match `/cmd` am Anfang einer Zeile (oder nach Whitespace).
  const before = context.matchBefore(/(^|\s)\/(\w*)$/)
  if (!before) return null
  if (before.from === context.pos && !context.explicit) return null
  const qMatch = before.text.match(/\/(\w*)$/)
  const q = qMatch ? qMatch[1].toLowerCase() : ""
  const fromAfterSep = before.text.startsWith(" ") || before.text.startsWith("\t")
    ? before.from + 1
    : before.from
  return {
    from: fromAfterSep,
    to:   context.pos,
    options: SLASH_COMMANDS.filter(c => !q || c.label.startsWith(q)).map(c => ({
      label:  `/${c.label}`,
      detail: window.t(c.detailKey),
      apply: (view, completion, from, to) => {
        const insert = c.apply
        const cursorAt = c.moveCursorOffset != null
          ? from + insert.length - c.moveCursorOffset
          : from + insert.length
        view.dispatch({
          changes: { from, to, insert },
          selection: { anchor: cursorAt }
        })
      }
    })),
    validFor: /^\/\w*$/
  }
}

// #384 Phase 2 (Hans, 2026-05-27): @-Mention-Autocomplete fuer
// App-Nutzer. Trigger: `@` am Wortanfang.
async function actorMentionCompletion(context) {
  // #667 (Hans): `@` adressiert App-NUTZER (Actors). Das `[`-Zeichen ist
  // hier bewusst NICHT erlaubt — `[[@…` ist ein Personen-Wikilink und
  // wird von wikilinkCompletion mit Person-/Org-KIs befüllt.
  const before = context.matchBefore(/(?:^|[\s(])@(\w*)$/)
  if (!before) return null
  if (before.from === context.pos && !context.explicit) return null
  const m = before.text.match(/@(\w*)$/)
  const q = m ? m[1] : ""
  // From-Position: das `@` selbst gehoert zur Completion (das `@` bleibt).
  const fromAfterSep = before.text.startsWith("@") ? before.from : before.from + 1
  let items = []
  try {
    const res = await fetch(`/actor_suggests?q=${encodeURIComponent(q)}`,
                             { headers: { Accept: "application/json" } })
    if (res.ok) items = await res.json()
  } catch (_) { /* silent */ }
  return {
    from: fromAfterSep,
    to:   context.pos,
    options: items.map(a => ({
      label:  `@${a.slug}`,
      detail: `${a.name}${a.kind === "agent" ? ` (${window.t("cm6.agent")})` : ""}`,
      apply:  `@${a.slug}`
    })),
    validFor: /^@\w*$/
  }
}

// #373 Phase C (Hans, 2026-05-26): Wikilink-Autocomplete als CM6-
// natives Completion. Wird aktiv, sobald der Cursor hinter `[[` steht.
// Liefert Title-Vorschlaege via /knowledge_items/suggest.
async function wikilinkCompletion(context) {
  // Suche `[[…` rueckwaerts ab dem Cursor bis zum NÄCHSTEN (nicht
  // frühesten) `[[`. #692 (Hans): `[` aus der Klasse ausschließen, sonst
  // greift die Query bei mehreren offenen `[[` in der Zeile vom ersten
  // `[[` und enthält Vortext (`[[ x [[Vibe` → q=" x [[Vibe").
  const before = context.matchBefore(/\[\[([^\]\n\[]*)$/)
  if (!before) return null
  // Wenn nicht-explizit getriggert und Query leer ist, nicht aufmachen.
  if (before.from === context.pos && !context.explicit) return null
  // #667 (Hans): `[[@…` schlägt PERSONEN (person/organization-KIs) vor
  // und fügt `[[@Name]]` ein; `[[…` ohne `@` schlägt alle KI-Titel vor.
  const raw      = before.text.slice(2)        // hinter `[[`
  const isPerson = raw.startsWith("@")
  const q        = isPerson ? raw.slice(1) : raw
  const url      = isPerson
    ? `/knowledge_items/suggest?item_type=person,organization&q=${encodeURIComponent(q)}`
    : `/knowledge_items/suggest?q=${encodeURIComponent(q)}`
  let items = []
  try {
    const res = await fetch(url, { headers: { Accept: "application/json" } })
    if (res.ok) {
      const data = await res.json()
      items = data.items || []
    }
  } catch (_) { /* netz weg, leeres dropdown */ }
  return {
    from: before.from + 2,            // hinter `[[`
    to:   context.pos,
    options: items.map(it => ({
      label:  isPerson ? `@${it.title}` : it.title,
      detail: it.aliases?.length ? it.aliases.join(", ") : (isPerson ? window.t("cm6.person") : it.item_type),
      apply:  (view, completion, from, to) => {
        // Append `]]` falls noch nicht im Doc, und den Cursor hinter
        // die `]]` setzen.
        const after = view.state.sliceDoc(to, to + 2)
        const insert = after === "]]" ? completion.label : `${completion.label}]]`
        view.dispatch({
          changes: { from, to, insert },
          selection: { anchor: from + insert.length }
        })
      }
    })),
    // #785 (Hans): Das BACKEND matcht bereits case-insensitiv als Substring
    // über Titel UND Aliase (LOWER(title) LIKE %q%). CM6 NICHT zusätzlich
    // clientseitig nachfiltern lassen — dessen Fuzzy-Filter wirft Mittendrin-
    // Treffer wie „ideal" → „Das ideale Tool" raus. filter:false zeigt die
    // Backend-Treffer 1:1. Ohne validFor wird pro Tastendruck neu abgefragt
    // (Backend übernimmt das Eingrenzen) statt eine veraltete Liste zu halten.
    filter: false
  }
}

// #446 (Hans, 2026-06-01): Farb-Palette fuers Edit-Modus-Kontextmenue,
// analog zur paragraph-actions-Bar im Read-Modus (gleiche Tailwind-
// Swatches: gelb=amber, rot=rose, gruen=emerald, blau=sky, lila=violet).
const HL_MENU_COLORS = [
  ["gelb",  "bg-amber-200",   "hover:bg-amber-300"],
  ["rot",   "bg-rose-200",    "hover:bg-rose-300"],
  ["gruen", "bg-emerald-200", "hover:bg-emerald-300"],
  ["blau",  "bg-sky-200",     "hover:bg-sky-300"],
  ["lila",  "bg-violet-200",  "hover:bg-violet-300"]
]
const HL_COLORS = HL_MENU_COLORS.map(c => c[0])
// Fuehrender Block-Marker (Bullet/nummerierte Liste/Blockquote/Heading)
// muss beim Wrappen AUSSERHALB der `==…==`-Klammer bleiben, sonst bricht
// das Listen-/Heading-Rendering — dieselbe Regel wie serverseitig in
// BodyHighlightWrapper (#449).
const BLOCK_PREFIX_RE = /^([ \t]*(?:[-*+] |\d+[.)] |>+ |#{1,6} ))/

export default class extends Controller {
  static targets = ["host", "textarea"]
  // #451 (Hans, 2026-06-01): autofocus — nach einem Antwort-Entwurf-Save
  // wird die ganze Replies-Section ersetzt (Fokus geht verloren). Mit
  // autofocus=true fokussiert das neu gemountete Compose-CM6 sich selbst,
  // damit der direkt folgende Strg+Umschalt+Enter (Entwurf veroeffentlichen)
  // ueberhaupt einen Tastatur-Fokus hat.
  static values  = { active: { type: Boolean, default: false },
                     autofocus: { type: Boolean, default: false } }

  connect() {
    // Aktivierungs-Logik:
    //   1. URL-Param `?cm6=1` / `?cm6=0` ueberschreibt alles (manueller Test).
    //   2. Sonst zaehlt activeValue (= ActorPreferences.cm6_editor).
    const url   = new URL(window.location.href)
    const param = url.searchParams.get("cm6")
    let enabled
    if (param === "1") enabled = true
    else if (param === "0") enabled = false
    else enabled = this.activeValue
    if (!enabled) return
    if (!this.hasTextareaTarget) return

    const ta = this.textareaTarget
    const initialDoc = ta.value || ""

    // #373 Hotfix (Hans, 2026-05-28): Wenn CM6 aktiv ist, sollen die
    // alten Textarea-basierten Autocomplete-Controller (wikilink,
    // cite) deaktiviert werden — sonst feuern bei `[[` zwei Listen
    // gleichzeitig (CM6-native + altes Wikilink-Popup). Wir
    // entfernen die jeweiligen Controller-Tokens vom Wurzel-Element,
    // Stimulus disconnected sie automatisch.
    const root = this.element
    if (root && root.dataset.controller) {
      root.dataset.controller = root.dataset.controller
        .split(/\s+/)
        .filter(t => t && t !== "wikilink-autocomplete" && t !== "cite-autocomplete")
        .join(" ")
    }

    // #373 Phase B (Hans, 2026-05-26): Heading-Levels visuell groesser,
    // damit Edit-Mode dem Read-Mode naeher kommt.
    const miolimHighlightStyle = HighlightStyle.define([
      { tag: tags.heading1, fontSize: "1.5em",  fontWeight: "700" },
      { tag: tags.heading2, fontSize: "1.3em",  fontWeight: "700" },
      { tag: tags.heading3, fontSize: "1.15em", fontWeight: "600" },
      { tag: tags.heading4, fontSize: "1.05em", fontWeight: "600" },
      { tag: tags.strong,   fontWeight: "700" },
      { tag: tags.emphasis, fontStyle: "italic" },
      { tag: tags.link,     color: "rgb(4 120 87)" }              // emerald-700
    ])

    this.view = new EditorView({
      state: EditorState.create({
        doc: initialDoc,
        extensions: [
          history(),
          autocompletion({
            override:    [wikilinkCompletion, actorMentionCompletion, slashCompletion],
            activateOnTyping: true,
            closeOnBlur: true
          }),
          // #373 Phase C (b): Tab/Shift-Tab fuer Indent/Outdent (auch
          // in Listen — CM6 erkennt Listen-Items als „indent context").
          // #391 (Hans, 2026-05-28): Ctrl/Cmd-Enter submitted das
          // umgebende Form (Regression nach CM6-Umstellung — vor CM6
          // schluckte die Textarea den Shortcut nicht).
          keymap.of([
            {
              // #451 (Hans, 2026-06-01): Mod-Enter / Mod-Shift-Enter
              // ueber die geteilte Routing-Logik (Entwurf/Senden/Publish).
              key: "Mod-Enter",
              run: (view) => {
                // CM6→Textarea-Sync via updateListener — bei einem
                // sofortigen Submit waere v.docChanged ggf. noch nicht
                // gefeuert. Hier nochmal explizit syncen, damit der
                // letzte Tastendruck garantiert mit ins Submit geht.
                ta.value = view.state.doc.toString()
                dispatchBladeShortcut({ shiftKey: false, contextEl: ta })
                return true
              }
            },
            {
              key: "Mod-Shift-Enter",
              run: (view) => {
                ta.value = view.state.doc.toString()
                dispatchBladeShortcut({ shiftKey: true, contextEl: ta })
                return true
              }
            },
            indentWithTab,
            ...defaultKeymap, ...historyKeymap,
            ...completionKeymap, ...closeBracketsKeymap]),
          markdown(),
          syntaxHighlighting(defaultHighlightStyle),
          syntaxHighlighting(miolimHighlightStyle),
          bracketMatching(),
          highlightActiveLine(),
          EditorView.lineWrapping,
          miolimDecorations,
          miolimDecorationTheme,
          EditorView.theme({
            "&": {
              // #373 Phase B+ (Hans, 2026-05-26): Font vom Container
              // erben (= body-Font-Stack), damit Edit-Modus optisch
              // exakt dem Read-Modus entspricht.
              fontSize: "14px",                        // = .markdown-body text-sm
              fontFamily: "inherit",
              color: "rgb(51 65 85)",                  // slate-700, wie .markdown-body
              border: "1px solid rgb(226 232 240)",    // slate-200
              borderRadius: "4px"
              // #403 Iter 4 (Hans, 2026-05-30): kein maxHeight mehr —
              // Edit-Bereich waechst auf volle Inhalts-Hoehe analog
              // Read-Mode. Section-Header ist sticky, Save-Klick
              // bleibt erreichbar. Outer-Scroll-Container handhabt
              // den Scroll, scrollTop-Restore funktioniert sauber.
            },
            ".cm-content": {
              padding: "8px",
              lineHeight: "1.55",
              fontFamily: "inherit"
            },
            // #373 Phase C (d) (Hans, 2026-05-26): Auf Mobile horizontale
            // Touch-Gesten an den Parent durchreichen, damit native
            // scroll-snap (blade-stack) zwischen Cards swipen kann.
            // Vertikales Scrollen im Editor bleibt moeglich.
            "@media (max-width: 767px)": {
              "&": { touchAction: "pan-y" },
              ".cm-content":  { touchAction: "pan-y" },
              ".cm-scroller": { touchAction: "pan-y" }
            },
            ".cm-focused": { outline: "none" },
            "&.cm-focused": { borderColor: "rgb(74 222 128)" },  // emerald-400
            ".cm-scroller": { overflow: "auto", fontFamily: "inherit" }
          }),
          EditorView.updateListener.of((v) => {
            if (v.docChanged) {
              ta.value = v.state.doc.toString()
              // #386 (Hans, 2026-05-27): Andere Stimulus-Controller
              // (buttons-when-filled, autosize, dirty-warn,
              // comment-autosave, description-toggle) hoeren auf
              // `input`-Events der Textarea. `ta.value = …` allein
              // feuert kein Event — wir muessen es synthetisch
              // dispatchen, sonst bleiben Save-Buttons unsichtbar +
              // Autosize-Hoehe stale + Dirty-State nicht markiert.
              ta.dispatchEvent(new Event("input", { bubbles: true }))
            }
          })
        ]
      })
    })

    // Textarea visuell verstecken, aber im DOM lassen (Submit liefert
    // weiterhin den Wert, plus autosize/autocomplete-Controller koennen
    // ungestoert ihre Listener halten).
    ta.style.display = "none"
    ta.dataset.cm6Hidden = "1"

    // CM6-Editor unter die Textarea einfuegen.
    ta.parentElement.insertBefore(this.view.dom, ta.nextSibling)

    // #373 Phase C (Hans, 2026-05-26): Wikilink-Pill-Click oeffnet
    // Stack-Card. Pill dispatcht `cm6:wikilink-click` mit Title; wir
    // schlagen Title via /knowledge_items/suggest?q=… nach, finden
    // exakten Match und navigieren via Turbo zur Stack-URL.
    this._onWikilinkClick = (e) => this.handleWikilinkClick(e)
    this.element.addEventListener("cm6:wikilink-click", this._onWikilinkClick)

    // #446 (Hans, 2026-06-01): Rechtsklick im Editor oeffnet das
    // Highlight-Kontextmenue (Edit-Modus-Pendant zur Read-Modus-Bar).
    this._onContextMenu = (e) => this.openHighlightMenu(e)
    this.view.dom.addEventListener("contextmenu", this._onContextMenu)

    // #451 (Hans, 2026-06-01): nach Re-Render mit autofocus den Cursor
    // direkt in dieses Editor-Feld setzen (Compose nach Entwurf-Save).
    if (this.autofocusValue) {
      requestAnimationFrame(() => this.view?.focus())
    }
  }

  async handleWikilinkClick(event) {
    const title = event.detail?.title
    if (!title) return
    try {
      const res = await fetch(
        `/knowledge_items/suggest?q=${encodeURIComponent(title)}`,
        { headers: { Accept: "application/json" } }
      )
      if (!res.ok) return
      const data = await res.json()
      const items = data.items || []
      const hit = items.find(i =>
        i.title?.toLowerCase() === title.toLowerCase() ||
        (i.aliases || []).some(a => a.toLowerCase() === title.toLowerCase())
      )
      if (!hit) {
        console.info(`cm6-editor: no KI found for [[${title}]]`)
        return
      }
      // Stack-Append via URL — blade-stack-controller synct beim
      // popstate/visit den Stack auf den neuen Param.
      const url = new URL(window.location.href)
      const existing = (url.searchParams.get("stack") || "").split(",").filter(Boolean)
      if (!existing.includes(hit.uuid)) existing.push(hit.uuid)
      url.searchParams.set("stack", existing.join(","))
      window.Turbo?.visit(url.pathname + url.search) || (window.location.href = url.toString())
    } catch (err) {
      console.warn("cm6-editor: wikilink-click failed", err)
    }
  }

  // #446: Rechtsklick-Menue mit den 5 Highlight-Farben (+ „keine" =
  // unwrap). Wirkt auf die aktuelle Selektion oder — ohne Selektion —
  // auf die angeklickte Zeile. Anders als im Read-Modus laeuft KEIN
  // Server-Call: der Body IST hier die editierbare CM6-Source, die
  // Aenderung geht ueber den normalen CM6→Textarea→Submit-Flow mit.
  openHighlightMenu(event) {
    if (!this.view) return
    event.preventDefault()
    this.closeHighlightMenu()

    // Zielbereich: nicht-leere Selektion gewinnt; sonst die angeklickte
    // Zeile (per Maus-Koordinaten, nicht der alte Cursor).
    const state = this.view.state
    const sel   = state.selection.main
    if (!sel.empty) {
      const multiline = state.doc.lineAt(sel.from).number !== state.doc.lineAt(sel.to).number
      this._hlTarget = { from: sel.from, to: sel.to, multiline }
    } else {
      const pos  = this.view.posAtCoords({ x: event.clientX, y: event.clientY })
      const line = state.doc.lineAt(pos == null ? sel.from : pos)
      this._hlTarget = { from: line.from, to: line.to, wholeLine: true, multiline: false }
    }

    const menu = document.createElement("div")
    menu.className = "cm6-hl-menu fixed z-50 flex items-center gap-1 bg-white " +
                     "border border-slate-200 rounded shadow-md p-1"
    HL_MENU_COLORS.forEach(([color, bg, hover]) => {
      const b = document.createElement("button")
      b.type = "button"
      b.title = window.t("cm6.highlight_color", { color: color })
      b.className = `w-6 h-6 rounded border border-slate-300 ${bg} ${hover} cursor-pointer`
      b.addEventListener("click", () => this.applyHighlight(color))
      menu.appendChild(b)
    })
    const none = document.createElement("button")
    none.type = "button"
    none.title = window.t("cm6.highlight_remove")
    none.textContent = "∅"
    none.className = "w-6 h-6 rounded border border-slate-300 bg-white hover:bg-slate-100 " +
                     "text-slate-500 text-sm leading-none cursor-pointer"
    none.addEventListener("click", () => this.applyHighlight("keine"))
    menu.appendChild(none)

    document.body.appendChild(menu)
    this._hlMenu = menu
    // Im Viewport halten.
    const mw = menu.offsetWidth, mh = menu.offsetHeight
    let left = event.clientX, top = event.clientY + 4
    if (left + mw > window.innerWidth)  left = window.innerWidth - mw - 4
    if (top + mh > window.innerHeight)  top  = event.clientY - mh - 4
    menu.style.left = `${Math.max(4, left)}px`
    menu.style.top  = `${Math.max(4, top)}px`

    // Schliessen bei Klick ausserhalb / Escape / Scroll. Capture-Phase,
    // damit es auch ueber CM6-eigene Listener hinweg greift; per setTimeout
    // wired, damit der oeffnende Rechtsklick es nicht sofort schliesst.
    this._hlClose = (e) => {
      if (e.type === "keydown" && e.key !== "Escape") return
      if (e.type === "mousedown" && this._hlMenu && this._hlMenu.contains(e.target)) return
      this.closeHighlightMenu()
    }
    setTimeout(() => {
      document.addEventListener("mousedown", this._hlClose, true)
      document.addEventListener("keydown",   this._hlClose, true)
      window.addEventListener("scroll",      this._hlClose, true)
    }, 0)
  }

  closeHighlightMenu() {
    if (this._hlClose) {
      document.removeEventListener("mousedown", this._hlClose, true)
      document.removeEventListener("keydown",   this._hlClose, true)
      window.removeEventListener("scroll",      this._hlClose, true)
      this._hlClose = null
    }
    if (this._hlMenu) { this._hlMenu.remove(); this._hlMenu = null }
    this._hlTarget = null
  }

  applyHighlight(color) {
    const view = this.view
    const t    = this._hlTarget
    if (!view || !t) { this.closeHighlightMenu(); return }
    const state = view.state
    let { from, to } = t

    // Fuehrenden Block-Marker aus dem Wrap-Bereich heraushalten (#449);
    // bei Ganz-Zeile zusaetzlich umschliessende Whitespace trimmen.
    if (!t.multiline) {
      const line = state.doc.lineAt(from)
      const m = line.text.match(BLOCK_PREFIX_RE)
      const markerEnd = m ? line.from + m[1].length : line.from
      if (from < markerEnd) from = markerEnd
      if (t.wholeLine) {
        const seg   = state.doc.sliceString(from, to)
        from += seg.match(/^\s*/)[0].length
        to   -= seg.match(/\s*$/)[0].length
      }
      if (to < from) to = from
    }

    if (color === "keine") {
      const change = this._unwrapAt(state, from, to)
      if (change) view.dispatch(change)
      this.closeHighlightMenu(); view.focus(); return
    }

    const text = state.doc.sliceString(from, to)
    if (text.length === 0) {
      // Leere Zeile/Selektion: leeren Highlight setzen, Cursor zwischen
      // `|` und `==` — der User tippt direkt in den Highlight hinein
      // (analog /highlight-Slash-Command).
      const insert = `==${color}|==`
      view.dispatch({ changes: { from, to, insert },
                      selection: { anchor: from + color.length + 3 } })
    } else {
      // Schon gewrappt? Nur umfaerben statt verschachteln.
      const core   = this._stripWrap(text) ?? text
      const insert = `==${color}|${core}==`
      view.dispatch({ changes: { from, to, insert },
                      selection: { anchor: from, head: from + insert.length } })
    }
    this.closeHighlightMenu()
    view.focus()
  }

  // Entfernt genau EINEN `==color|…==`-Wrap, der [from,to] schneidet
  // (zeilen-lokal). Liefert ein dispatch-Spec oder null.
  _unwrapAt(state, from, to) {
    const line = state.doc.lineAt(from)
    const re = new RegExp(`==(?:${HL_COLORS.join("|")})\\|([^=]{1,4000}?)==(?:\\^[a-f0-9]{8})?`, "g")
    let m
    while ((m = re.exec(line.text)) !== null) {
      const wrapFrom = line.from + m.index
      const wrapTo   = wrapFrom + m[0].length
      if (wrapFrom <= to && wrapTo >= from) {
        return { changes: { from: wrapFrom, to: wrapTo, insert: m[1] },
                 selection: { anchor: wrapFrom, head: wrapFrom + m[1].length } }
      }
    }
    return null
  }

  // Wenn `text` exakt EIN `==color|core==(^id)?` ist, gib core zurueck;
  // sonst null.
  _stripWrap(text) {
    const m = text.match(
      new RegExp(`^==(?:${HL_COLORS.join("|")})\\|([^=]{1,4000}?)==(?:\\^[a-f0-9]{8})?$`))
    return m ? m[1] : null
  }

  disconnect() {
    this.closeHighlightMenu()
    if (this._onContextMenu && this.view) {
      this.view.dom.removeEventListener("contextmenu", this._onContextMenu)
      this._onContextMenu = null
    }
    if (this._onWikilinkClick) {
      this.element.removeEventListener("cm6:wikilink-click", this._onWikilinkClick)
      this._onWikilinkClick = null
    }
    if (this.view) {
      this.view.destroy()
      this.view = null
    }
    if (this.hasTextareaTarget && this.textareaTarget.dataset.cm6Hidden === "1") {
      this.textareaTarget.style.display = ""
      delete this.textareaTarget.dataset.cm6Hidden
    }
  }
}
