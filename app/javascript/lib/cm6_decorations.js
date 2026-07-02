// #373 Phase B (Hans, 2026-05-26): CM6-Decorations fuer miolim-
// Markup-Konventionen. Wird in `cm6_editor_controller.js` ueber
// Object-Spread an die Extension-Liste angehaengt.
//
// Aktuell drin:
//   - Wikilink-Pill: `[[Title]]` / `[[Title|Alias]]` / `[[Title^anchor]]`
//     wird visuell als gerundeter Pill mit Title (oder Alias) gerendert.
//     Wenn der Cursor in den Range eindringt, klappt die Syntax wieder
//     auf wie in Obsidian's „Source-with-Live-Preview".
//   - Highlight-Color: `==color|text==` bekommt einen passenden
//     Background-Farbton; Syntax bleibt sichtbar.
//   - Block-Anker: `^abc123` als kleines `§`-Marker-Pill.
//   - Citation-Pill: `((Title))` analog Wikilink, dezenter Stil.

import { EditorView, Decoration, WidgetType, ViewPlugin } from "@codemirror/view"
import { RangeSetBuilder } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"

// ─── Regex-Patterns ──────────────────────────────────────────────
// Wikilinks: `[[Title]]`, `[[Title|Alias]]`, `[[Title|https://…]]`,
//            `[[Title#Heading]]`, `[[Title^anchor]]`.
// #692 (Hans): `[` ausgeschlossen → engstes `[[…]]` statt weitestes.
const WIKILINK_RE = /\[\[([^\]|#\^\[]+)(?:#([^\]|]+))?(?:\^([^\]|]+))?(?:\|([^\]]+))?\]\]/g

// Highlights: parallel zur server-seitigen Regex (knowledge_markdown.rb).
// Erlaubte Syntaxen:
//   ==Text==                 → gelb (Default)
//   ==Text|rot==             → Suffix-Form
//   ==rot|Text==             → Prefix-Form
//   ==|rot Text==            → Prefix-Form mit fuehrendem Pipe
//   ==rot: Text==            → Prefix-Form mit Doppelpunkt
// Wir matchen `==(?!\s)([^=]{1,4000}?)==` analog zum Server und parsen
// das Inner-Token in einer zweiten Stufe.
// #387 Phase A (Hans, 2026-05-28): optionaler 8-Hex-Anker direkt am
// Wrap-Ende — `==color|text==^a3f2c9d1`. Das Replace-Widget
// konsumiert den ganzen Wrap inkl. Anker, sodass der Anker im Read-
// Modus nicht als roher Text uebrig bleibt.
// #387 Phase B (Hans, 2026-05-30): optionaler Tag-Suffix
// `#tag1#tag2` direkt nach dem Anker — wird vom Decoration-Widget
// mit konsumiert, damit die Tags im Edit-Mode nicht als rohe Hashes
// uebrig bleiben.
const HIGHLIGHT_RE = /==(?!\s)([^=]{1,4000}?)==(?:\^([a-f0-9]{8}))?((?:#[a-zA-Z0-9_-]+)*)/g
const HIGHLIGHT_COLORS = ["gelb", "rot", "gruen", "blau", "lila"]
const HIGHLIGHT_PREFIX_RE = new RegExp(
  `^\\|?(${HIGHLIGHT_COLORS.join('|')})\\s*[|:\\s]\\s*(.+)$`, "i"
)
const HIGHLIGHT_SUFFIX_RE = new RegExp(
  `^(.+?)\\|(${HIGHLIGHT_COLORS.join('|')})$`, "i"
)

function parseHighlightInner(inner) {
  let m = inner.match(HIGHLIGHT_PREFIX_RE)
  if (m) return { color: m[1].toLowerCase(), text: m[2] }
  m = inner.match(HIGHLIGHT_SUFFIX_RE)
  if (m) return { color: m[2].toLowerCase(), text: m[1] }
  return { color: "gelb", text: inner }
}

// Block-Anker: `^block-N` oder `^xxxxxx` (6 hex chars stable id) am
// Zeilenende oder vor Whitespace. Wir akzeptieren beide hier.
const BLOCK_ANCHOR_RE = /\^(block-\d+|[0-9a-z]{6})(?=\s|$)/g

// References: `((Title))` oder `((Title|Display))`
const REFERENCE_RE = /\(\(([^)|]+)(?:\|([^)]+))?\)\)/g

// Externe URL-Links im Markdown-Format `[text](url)`. URL ist
// pflichtmaessig http(s)://, weil relative Pfade selten gewollt sind
// und gegenueber `[[Wikilinks]]` als Schreibvariante anders gehandhabt
// werden sollen.
const URL_LINK_RE = /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g

// #384 Phase 2 (Hans, 2026-05-27): @-Mention auf App-Nutzer.
// Slug-Konvention `@<lowercase-name>`. Match analog server-side
// in app/services/knowledge_markdown/actor_mentions.rb.
// Vorher MUSS Whitespace/EOL stehen — keine Klammer (kollidiert mit
// Citations `[@source]` und Markdown-Links `(@…)`).
const ACTOR_MENTION_RE = /(?:^|(?<=\s))@([a-zA-Z][a-zA-Z0-9_-]{1,40})(?![a-zA-Z0-9_\-@.])/g

// #534 (Hans, 2026-06-06): Aufgaben-Referenz `[[#id]]` / `[[#id|Alias]]`.
// Parallel zur server-seitigen TASK_REF_RE (wikilinks.rb). WIKILINK_RE oben
// schliesst `#` im Title aus, daher kein Konflikt — eigener Pass.
const TASK_REF_RE = /\[\[#(\d+)(?:\|([^\]]+))?\]\]/g

// Farb-Klassen analog zum bestehenden ==color|text==-Rendering aus
// dem MD-Renderer (knowledge_markdown/highlight.rb).
const COLOR_CLASSES = {
  gelb:  "cm6-hl cm6-hl-gelb",
  rot:   "cm6-hl cm6-hl-rot",
  gruen: "cm6-hl cm6-hl-gruen",
  blau:  "cm6-hl cm6-hl-blau",
  lila:  "cm6-hl cm6-hl-lila"
}

// ─── Widgets ─────────────────────────────────────────────────────

// In-Memory-Cache fuer Title-Resolve. Pro Editor-Lifetime gepflegt;
// CM6 zerstoert den ViewPlugin bei Disconnect, dann wird er neu
// gebaut. Der Cache ist Modul-global, damit mehrere CM6-Mount-Points
// (z.B. mehrere Edit-Blades im Stack) ihn teilen koennen.
const titleResolveCache = new Map() // key: title.toLowerCase(), value: "hit" | "miss" | "pending"

function fetchTitleStatus(title) {
  const key = title.toLowerCase()
  if (titleResolveCache.has(key)) return
  titleResolveCache.set(key, "pending")
  fetch(`/knowledge_items/suggest?q=${encodeURIComponent(title)}`,
        { headers: { Accept: "application/json" } })
    .then(r => r.ok ? r.json() : { items: [] })
    .then(data => {
      const hit = (data.items || []).some(i =>
        i.title?.toLowerCase() === key ||
        (i.aliases || []).some(a => a.toLowerCase() === key))
      titleResolveCache.set(key, hit ? "hit" : "miss")
      // Notify any mounted CM6 view to repaint.
      document.dispatchEvent(new CustomEvent("cm6:wikilink-resolved", {
        detail: { title: key, status: hit ? "hit" : "miss" }
      }))
    })
    .catch(_ => titleResolveCache.set(key, "miss"))
}

// #534: Title-Resolve für Aufgaben-Refs `[[#id]]`. Analog zu
// titleResolveCache, aber per Task-ID. Wert: { status, title }.
const taskLabelCache = new Map() // key: id (string), value: {status:"pending"|"hit"|"miss", title}

function fetchTaskLabel(id) {
  if (taskLabelCache.has(id)) return
  taskLabelCache.set(id, { status: "pending", title: null })
  fetch(`/tasks/${encodeURIComponent(id)}/ref_label`,
        { headers: { Accept: "application/json" } })
    .then(r => r.ok ? r.json() : null)
    .then(data => {
      if (data && data.found) {
        taskLabelCache.set(id, { status: "hit", title: data.title || "" })
      } else {
        taskLabelCache.set(id, { status: "miss", title: null })
      }
      document.dispatchEvent(new CustomEvent("cm6:taskref-resolved", { detail: { id } }))
    })
    .catch(_ => {
      taskLabelCache.set(id, { status: "miss", title: null })
      document.dispatchEvent(new CustomEvent("cm6:taskref-resolved", { detail: { id } }))
    })
}

// #534: Pille für eine Aufgaben-Referenz. Zeigt „#id Titel" (sobald
// aufgelöst), sonst „#id". Nicht-interaktiv (wie Headings) — Klick setzt
// nur den Cursor, damit die Source editierbar wird.
class TaskRefPillWidget extends WidgetType {
  constructor(id, alias, status, title) {
    super()
    this.id = id
    this.alias = alias || null
    this.status = status   // "pending" | "hit" | "miss"
    this.title = title || null
  }
  eq(other) {
    return other.id === this.id && other.alias === this.alias &&
           other.status === this.status && other.title === this.title
  }
  toDOM() {
    const el = document.createElement("span")
    const missing = this.status === "miss"
    el.className = missing ? "cm6-taskref-pill cm6-taskref-missing" : "cm6-taskref-pill"
    let text
    if (this.alias) text = this.alias
    else if (this.status === "hit") text = `#${this.id} ${this.title}`.trim()
    else text = `#${this.id}`
    el.textContent = text
    el.title = missing
      ? `[[#${this.id}]] — Aufgabe nicht gefunden`
      : `[[#${this.id}]] — Aufgabe`
    return el
  }
  ignoreEvent() { return false }
}

class WikilinkPillWidget extends WidgetType {
  constructor(label, title, status) {
    super()
    this.label = label
    this.title = title
    this.status = status   // "hit" | "miss" | "pending"
  }
  eq(other) {
    return other.label === this.label && other.title === this.title && other.status === this.status
  }
  toDOM() {
    const el = document.createElement("span")
    const cls = this.status === "miss" ? "cm6-wikilink-pill cm6-wikilink-missing" : "cm6-wikilink-pill"
    el.className = cls
    el.textContent = this.label
    el.title = this.status === "miss"
      ? `[[${this.title}]] — keine KI mit diesem Title (Klick: Vorschaege)`
      : `[[${this.title}]] — Klick: oeffnen`
    el.dataset.cm6WikilinkTitle = this.title
    el.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      el.dispatchEvent(new CustomEvent("cm6:wikilink-click", {
        bubbles: true,
        detail: { title: this.title }
      }))
    })
    return el
  }
  ignoreEvent(event) {
    return event.type === "click" || event.type === "mousedown"
  }
}

class ReferencePillWidget extends WidgetType {
  constructor(label) { super(); this.label = label }
  eq(other) { return other.label === this.label }
  toDOM() {
    const el = document.createElement("span")
    el.className = "cm6-reference-pill"
    el.textContent = this.label
    return el
  }
  ignoreEvent() { return false }
}

class HighlightWidget extends WidgetType {
  constructor(text, color) { super(); this.text = text; this.color = color }
  eq(other) { return other.text === this.text && other.color === this.color }
  toDOM() {
    const el = document.createElement("span")
    el.className = `cm6-hl cm6-hl-${this.color}`
    el.textContent = this.text
    return el
  }
  ignoreEvent() { return false }
}

class UrlLinkWidget extends WidgetType {
  constructor(label, url) { super(); this.label = label; this.url = url }
  eq(other) { return other.label === this.label && other.url === this.url }
  toDOM() {
    const a = document.createElement("a")
    a.className = "cm6-url-link"
    a.textContent = this.label
    a.href = this.url
    a.target = "_blank"
    a.rel = "noopener noreferrer"
    a.title = this.url
    // Click bubbelt nicht zum CM6-Editor-Click-Handler, sonst klappt
    // die Source auf.
    a.addEventListener("click", (e) => e.stopPropagation())
    return a
  }
  ignoreEvent(event) {
    return event.type === "click" || event.type === "mousedown"
  }
}

class ActorMentionWidget extends WidgetType {
  constructor(slug) { super(); this.slug = slug }
  eq(other) { return other.slug === this.slug }
  toDOM() {
    const el = document.createElement("span")
    el.className = "cm6-actor-mention"
    el.textContent = `@${this.slug}`
    el.title = `@${this.slug} — App-Nutzer-Adressat`
    return el
  }
  ignoreEvent() { return false }
}

class BlockAnchorWidget extends WidgetType {
  constructor(id) { super(); this.id = id }
  eq(other) { return other.id === this.id }
  toDOM() {
    const el = document.createElement("span")
    el.className = "cm6-block-anchor"
    el.textContent = "§"
    el.title = `Block-Anker ${this.id}`
    return el
  }
  ignoreEvent() { return true }
}

// #448 (Hans, 2026-06-01): Bullet-Widget — ersetzt den Listen-Marker
// `-`/`*`/`+` im Edit-Modus durch ein gerendertes `•`, analog zum Read-
// Modus (Obsidian-Live-Preview). Nummerierte Listen behalten ihre Zahl.
class ListBulletWidget extends WidgetType {
  eq() { return true }
  toDOM() {
    const el = document.createElement("span")
    el.className = "cm6-list-bullet"
    el.textContent = "•"
    return el
  }
  ignoreEvent() { return true }
}

// ─── Decoration-Builder ──────────────────────────────────────────

// Pro View laufen wir einmal durch das gesamte Doc und sammeln
// Decorations. Performance ist fuer typische KI-Body-Groessen (~10kb)
// vernachlaessigbar. Bei sehr grossen Docs koennte man auf
// Visible-Range einschraenken; das machen wir falls noetig spaeter.
function buildDecorations(view) {
  const builder = new RangeSetBuilder()
  const doc = view.state.doc.toString()
  const cursor = view.state.selection.main

  // Helfer: liefert true, wenn der Cursor INNERHALB von [from, to]
  // liegt oder die Selektion das Range schneidet. In dem Fall lassen
  // wir die Decoration weg, damit der User die Syntax sieht und
  // editieren kann.
  const cursorIntersects = (from, to) =>
    cursor.from <= to && cursor.to >= from

  // 1) Wikilinks
  const wlRanges = []
  WIKILINK_RE.lastIndex = 0
  for (const m of doc.matchAll(WIKILINK_RE)) {
    if (m[0].includes("\n")) continue
    const from = m.index
    const to   = from + m[0].length
    const title = m[1].trim()
    const alias = m[4]?.trim()
    const label = alias && !/^https?:\/\//i.test(alias) ? alias : title
    wlRanges.push({ from, to, label, title })
  }

  // 1b) Aufgaben-Refs `[[#id]]` (#534)
  const taskRefRanges = []
  TASK_REF_RE.lastIndex = 0
  for (const m of doc.matchAll(TASK_REF_RE)) {
    if (m[0].includes("\n")) continue
    const from = m.index
    const to   = from + m[0].length
    taskRefRanges.push({ from, to, id: m[1], alias: m[2]?.trim() || null })
  }

  // 2) Highlights — wir replacen den ganzen `==…==`-Range mit einem
  // Widget, das nur den Text zeigt (mit Background-Color). Sobald der
  // Cursor in den Range eindringt, klappt die Source wieder auf
  // (analog zu Wikilinks). Inner-Token wird in einer zweiten Stufe
  // geparsed, damit alle Server-Syntaxen klappen.
  // #402 Bug-#1-Fix2 (Hans, 2026-05-29): Multi-Line-Highlights
  // (`==…\n…==`) ueberspringen — CM6 verbietet Replace-Decorations
  // ueber Zeilenumbrueche (`RangeError: Decorations that replace line
  // breaks may not be specified via plugins`), was beim Scrollen das
  // gesamte Rendering kollabieren laesst. Source bleibt sichtbar, der
  // Read-Modus rendert sie weiterhin als `<mark>...</mark>`.
  const hlRanges = []
  HIGHLIGHT_RE.lastIndex = 0
  for (const m of doc.matchAll(HIGHLIGHT_RE)) {
    if (m[0].includes("\n")) continue
    const from = m.index
    const to   = from + m[0].length
    const inner = m[1]
    const { color, text } = parseHighlightInner(inner)
    hlRanges.push({ from, to, text, color })
  }

  // 3) Block-Anker — replace-Widget
  const anchorRanges = []
  BLOCK_ANCHOR_RE.lastIndex = 0
  for (const m of doc.matchAll(BLOCK_ANCHOR_RE)) {
    const from = m.index
    const to   = from + m[0].length
    anchorRanges.push({ from, to, id: m[1] })
  }

  // 4) Citation-References
  const refRanges = []
  REFERENCE_RE.lastIndex = 0
  for (const m of doc.matchAll(REFERENCE_RE)) {
    if (m[0].includes("\n")) continue
    const from = m.index
    const to   = from + m[0].length
    const title = m[1].trim()
    const alias = m[2]?.trim()
    refRanges.push({ from, to, label: alias || title })
  }

  // 4a) @-Mentions auf App-Nutzer.
  const mentionRanges = []
  ACTOR_MENTION_RE.lastIndex = 0
  for (const m of doc.matchAll(ACTOR_MENTION_RE)) {
    // matchAll macht das `(?<=...)` zur Look-Behind — m.index ist der
    // Start des Match (= das `@`-Zeichen).
    const from = m.index
    const to   = from + m[0].length
    mentionRanges.push({ from, to, slug: m[1] })
  }

  // 4b) Externe URL-Links `[text](url)` — Hans-Feedback #373 Phase B/C:
  // werden bisher nicht visuell als Link gerendert. Wir replacen den
  // gesamten Range durch ein <a>-Widget. Beim Cursor-Eintritt klappt
  // die Source wieder auf, identisch zur Wikilink-Logik.
  const urlRanges = []
  URL_LINK_RE.lastIndex = 0
  for (const m of doc.matchAll(URL_LINK_RE)) {
    if (m[0].includes("\n")) continue
    const from = m.index
    const to   = from + m[0].length
    urlRanges.push({ from, to, label: m[1].trim(), url: m[2] })
  }

  // 5) Emphasis-Marker (Bold/Italic) verstecken, wenn Cursor nicht
  // drin ist — Hans-Feedback #373 Phase B: Sterne sollen weg, wenn
  // man nicht gerade an der Bold/Italic-Stelle editiert.
  // Wir nutzen die Lezer-Syntax-Tree-API von @codemirror/lang-markdown
  // um StrongEmphasis/Emphasis-Knoten samt ihren EmphasisMark-Children
  // zu finden — robust gegen verschachtelte Faelle.
  const markerRanges = []
  // #448 (Hans, 2026-06-01): Listen-Bullets `- * +` -> `•`. Separater
  // Range-Typ, weil hier ein Widget ersetzt (nicht nur versteckt wird).
  const bulletRanges = []
  try {
    syntaxTree(view.state).iterate({
      from: 0, to: doc.length,
      enter(node) {
        if (node.name === "StrongEmphasis" || node.name === "Emphasis") {
          if (cursorIntersects(node.from, node.to)) return
          // EmphasisMark-Kindknoten = die Sterne selbst.
          let child = node.node.firstChild
          while (child) {
            if (child.name === "EmphasisMark") {
              markerRanges.push({ from: child.from, to: child.to })
            }
            child = child.nextSibling
          }
        }
        // #448: Heading-Marks (`#`..`######`) verstecken, wenn der Cursor
        // nicht in der Zeile ist — der Heading-Text bleibt (groesser via
        // miolimHighlightStyle), nur die Hashes verschwinden. Inkl. der
        // direkt folgenden Spaces, damit kein Einzug uebrig bleibt.
        if (/^ATXHeading[1-6]$/.test(node.name)) {
          const line = view.state.doc.lineAt(node.from)
          if (cursorIntersects(line.from, line.to)) return
          let child = node.node.firstChild
          while (child) {
            if (child.name === "HeaderMark") {
              let to = child.to
              while (to < line.to && (doc[to] === " " || doc[to] === "\t")) to++
              markerRanges.push({ from: child.from, to })
            }
            child = child.nextSibling
          }
        }
        // #448: Bullet-Listen-Marker durch `•` ersetzen (nummerierte
        // Listen `1.`/`1)` bleiben, deren Zahl ist Inhalt). Reveal, wenn
        // der Cursor in der Zeile ist.
        if (node.name === "ListMark") {
          const markText = doc.slice(node.from, node.to)
          if (!/^[-*+]$/.test(markText)) return
          const line = view.state.doc.lineAt(node.from)
          if (cursorIntersects(line.from, line.to)) return
          bulletRanges.push({ from: node.from, to: node.to })
        }
      }
    })
  } catch (e) {
    // Falls die Markdown-Extension noch nicht geladen ist, einfach
    // ueberspringen — Marker bleiben dann sichtbar.
  }

  // Decorations in sortierter Reihenfolge in den Builder schieben.
  // Wir muessen RangeSetBuilder strikt sortiert befuellen, daher
  // sammeln + sortieren.
  const all = []
  for (const r of wlRanges) {
    if (cursorIntersects(r.from, r.to)) continue
    // Async title-resolve: kickt einen Fetch, wenn noch nicht gecacht.
    // Beim Resolve dispatchen wir `cm6:wikilink-resolved`, was den
    // ViewPlugin zum Re-Build triggert.
    const cacheKey = r.title.toLowerCase()
    if (!titleResolveCache.has(cacheKey)) fetchTitleStatus(r.title)
    const status = titleResolveCache.get(cacheKey) || "pending"
    all.push({
      from: r.from, to: r.to,
      deco: Decoration.replace({ widget: new WikilinkPillWidget(r.label, r.title, status) })
    })
  }
  // 1b) Aufgaben-Refs `[[#id]]` (#534) — async Title-Resolve per Task-ID.
  for (const r of taskRefRanges) {
    if (cursorIntersects(r.from, r.to)) continue
    if (!taskLabelCache.has(r.id)) fetchTaskLabel(r.id)
    const cached = taskLabelCache.get(r.id) || { status: "pending", title: null }
    all.push({
      from: r.from, to: r.to,
      deco: Decoration.replace({
        widget: new TaskRefPillWidget(r.id, r.alias, cached.status, cached.title)
      })
    })
  }
  for (const r of hlRanges) {
    if (cursorIntersects(r.from, r.to)) {
      // Cursor in der Highlight-Source: nicht replacen, aber den
      // sichtbaren Inhalt weiter mit Background-Color einfaerben, damit
      // man weiss, was man editiert. Mark-Decoration setzt eine Klasse
      // auf den Range.
      all.push({
        from: r.from, to: r.to,
        deco: Decoration.mark({ class: `cm6-hl cm6-hl-${r.color}` })
      })
    } else {
      all.push({
        from: r.from, to: r.to,
        deco: Decoration.replace({ widget: new HighlightWidget(r.text, r.color) })
      })
    }
  }
  for (const r of anchorRanges) {
    if (cursorIntersects(r.from, r.to)) continue
    all.push({
      from: r.from, to: r.to,
      deco: Decoration.replace({ widget: new BlockAnchorWidget(r.id) })
    })
  }
  for (const r of refRanges) {
    if (cursorIntersects(r.from, r.to)) continue
    all.push({
      from: r.from, to: r.to,
      deco: Decoration.replace({ widget: new ReferencePillWidget(r.label) })
    })
  }
  for (const r of urlRanges) {
    if (cursorIntersects(r.from, r.to)) continue
    all.push({
      from: r.from, to: r.to,
      deco: Decoration.replace({ widget: new UrlLinkWidget(r.label, r.url) })
    })
  }
  for (const r of mentionRanges) {
    if (cursorIntersects(r.from, r.to)) continue
    all.push({
      from: r.from, to: r.to,
      deco: Decoration.replace({ widget: new ActorMentionWidget(r.slug) })
    })
  }
  for (const r of markerRanges) {
    all.push({
      from: r.from, to: r.to,
      deco: Decoration.replace({})  // leerer Replace = unsichtbar
    })
  }
  // #448: Bullet-Marker durch `•`-Widget ersetzen.
  for (const r of bulletRanges) {
    all.push({
      from: r.from, to: r.to,
      deco: Decoration.replace({ widget: new ListBulletWidget() })
    })
  }
  all.sort((a, b) => a.from - b.from || a.to - b.to)
  for (const r of all) builder.add(r.from, r.to, r.deco)
  return builder.finish()
}

export const miolimDecorations = ViewPlugin.fromClass(class {
  constructor(view) {
    this.view = view
    this.decorations = buildDecorations(view)
    // Bei async Title-Resolve repainten.
    this._onResolved = () => {
      this.decorations = buildDecorations(this.view)
      this.view.update([])  // erzwingt re-render via leere Transaction
    }
    document.addEventListener("cm6:wikilink-resolved", this._onResolved)
    document.addEventListener("cm6:taskref-resolved", this._onResolved)  // #534
  }
  update(u) {
    if (u.docChanged || u.selectionSet || u.viewportChanged) {
      this.decorations = buildDecorations(u.view)
    }
  }
  destroy() {
    document.removeEventListener("cm6:wikilink-resolved", this._onResolved)
    document.removeEventListener("cm6:taskref-resolved", this._onResolved)  // #534
  }
}, { decorations: v => v.decorations })

// Theme-CSS fuer die Widget-Klassen. `EditorView.theme()` gibt
// hoehere Spezifitaet als baseTheme (Hans-Feedback: Highlight-Color
// rendert nicht — Tailwind-Preflight oder andere Klassen
// ueberschrieben das baseTheme).
export const miolimDecorationTheme = EditorView.theme({
  ".cm6-wikilink-pill": {
    display: "inline-block",
    background: "rgb(220 252 231)",                 // emerald-100
    color:      "rgb(4 120 87)",                    // emerald-700
    border:     "1px solid rgb(167 243 208)",       // emerald-200
    borderRadius: "4px",
    padding: "0 4px",
    margin: "0 1px",
    fontSize: "0.95em",
    cursor: "pointer"
  },
  ".cm6-wikilink-pill:hover": {
    background: "rgb(187 247 208)"                  // emerald-200
  },
  // #373 Phase C (e): Missing-Wikilink (Title aufgrund von Cache-
  // Resolve nicht gefunden) bekommt rote Optik — analog zur Read-View.
  ".cm6-wikilink-pill.cm6-wikilink-missing": {
    background: "rgb(254 226 226)",                 // red-100
    color:      "rgb(153 27 27)",                   // red-800
    border:     "1px dashed rgb(252 165 165)"       // red-300 dashed
  },
  ".cm6-wikilink-pill.cm6-wikilink-missing:hover": {
    background: "rgb(254 202 202)"                  // red-200
  },
  ".cm6-actor-mention": {
    display: "inline-block",
    background: "rgb(224 242 254)",                 // sky-100
    color:      "rgb(7 89 133)",                    // sky-800
    borderRadius: "4px",
    padding: "0 4px",
    margin: "0 1px",
    fontSize: "0.95em",
    fontWeight: "500"
  },
  // #534: Aufgaben-Ref-Pille `[[#id]]` — sky, analog zum Read-Mode-Link
  // (wikilink-task, text-sky-700).
  ".cm6-taskref-pill": {
    display: "inline-block",
    background: "rgb(224 242 254)",                 // sky-100
    color:      "rgb(3 105 161)",                   // sky-700
    border:     "1px solid rgb(186 230 253)",       // sky-200
    borderRadius: "4px",
    padding: "0 4px",
    margin: "0 1px",
    fontSize: "0.95em",
    cursor: "text"
  },
  ".cm6-taskref-pill.cm6-taskref-missing": {
    background: "rgb(255 228 230)",                 // rose-100
    color:      "rgb(190 18 60)",                   // rose-700
    border:     "1px dashed rgb(253 164 175)"       // rose-300 dashed
  },
  ".cm6-url-link": {
    color: "rgb(4 120 87)",                          // emerald-700, wie Read-View
    textDecoration: "underline",
    textUnderlineOffset: "2px",
    cursor: "pointer"
  },
  ".cm6-url-link:hover": {
    color: "rgb(6 95 70)"                            // emerald-800
  },
  ".cm6-reference-pill": {
    display: "inline-block",
    background: "rgb(254 226 226)",                 // red-100
    color:      "rgb(153 27 27)",                   // red-800
    border:     "1px solid rgb(252 165 165)",       // red-300
    borderRadius: "4px",
    padding: "0 4px",
    margin: "0 1px",
    fontStyle: "italic",
    fontSize: "0.9em"
  },
  // #448: Bullet-Ersatz fuer Listen-Marker im Edit-Modus.
  ".cm6-list-bullet": {
    color: "rgb(100 116 139)",                       // slate-500
    fontWeight: "700"
  },
  ".cm6-block-anchor": {
    display: "inline-block",
    color: "rgb(100 116 139)",                       // slate-500
    fontSize: "0.85em",
    marginLeft: "2px",
    cursor: "default"
  },
  ".cm6-hl": {
    padding: "0 1px",
    borderRadius: "2px"
  },
  // !important, weil Tailwind-Preflight `span { background: ... }`-
  // Resets aufweisen kann und unsere baseTheme-Regeln ueberschreibt.
  ".cm6-hl-gelb":  { background: "rgb(254 240 138) !important" }, // yellow-200
  ".cm6-hl-rot":   { background: "rgb(254 202 202) !important" }, // red-200
  ".cm6-hl-gruen": { background: "rgb(187 247 208) !important" }, // emerald-200
  ".cm6-hl-blau":  { background: "rgb(191 219 254) !important" }, // blue-200
  ".cm6-hl-lila":  { background: "rgb(233 213 255) !important" }  // purple-200
})
