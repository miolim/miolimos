// #564: DIE eine Routing-Tabelle des Blade-Stacks — Stack-ID ↔ Card-URL.
//
// Vorher existierte das Mapping ZWEIMAL in blade_stack_controller.js:
// als kind→URL-Switch in _onAppendEvent UND als Prefix→URL-Kette in
// _urlForStackId. Beide drifteten (#563 war ein Symptom dieser Klasse:
// ein Pfad kannte eine Route, der andere nicht). Jetzt leiten sich beide
// Lookups aus DERSELBEN Tabelle ab — eine neue Blade-Art wird genau
// EINMAL hier eingetragen.
//
// Jede Zeile: kind (blade-link/Sidebar-Event), stackId(id), url(id…).
// Reihenfolge der PREFIX-Auflösung ist signifikant (längere Prefixe wie
// list:topic: vor list:).
const ROUTES = [
  // #350: list:topic:<slug> ODER list:topic:<slug>:<tab>
  { kind: "topic_list", prefix: "list:topic:",
    stackId: id => `list:topic:${id}`,
    url: rest => {
      const sep = rest.indexOf(":")
      if (sep > 0) {
        const slug = rest.slice(0, sep), tab = rest.slice(sep + 1)
        return `/topics/${encodeURIComponent(slug)}/list_card?tab=${encodeURIComponent(tab)}`
      }
      return `/topics/${encodeURIComponent(rest)}/list_card`
    } },
  // #418: Listen-Blade aller Items mit einem Tag.
  { kind: "tag_list", prefix: "list:tag:",
    stackId: id => `list:tag:${id}`,
    url: rest => `/tags/${encodeURIComponent(rest)}/list_card` },
  // #352: Rendering-Blade fuer einen Topic-Work-Tree (nur Restore, kein kind).
  { prefix: "render:topic:", url: rest => `/topics/${encodeURIComponent(rest)}/render_card` },
  // #343/#352-follow: Reference-Blades (nur Restore).
  { prefix: "refs:ki:",    url: rest => `/knowledge_items/${encodeURIComponent(rest)}/refs_card` },
  { prefix: "refs:topic:", url: rest => `/topics/${encodeURIComponent(rest)}/refs_card` },
  // #163 Phase 5a-2: generisches Listen-Blade — id ist der List-Typ
  // (Endpoint-Konvention /:resource/list_card).
  { kind: "list", prefix: "list:",
    stackId: id => `list:${id}`,
    // #618 v2: Inbox-Routen leben unter path: "inbox" — die generische
    // /:resource/list_card-Konvention träfe /inbox_items/list_card (404).
    url: rest => rest === "inbox_items" ? "/inbox/list_card"
                                        : `/${encodeURIComponent(rest)}/list_card` },
  { kind: "topic", prefix: "topic:",
    stackId: id => `topic:${id}`,
    url: rest => `/topics/${encodeURIComponent(rest)}/card` },
  // #592 Z2: Fokusansicht auf einen Baum-Knoten.
  { kind: "tree_focus", prefix: "treefocus:",
    stackId: id => `treefocus:${id}`,
    url: rest => `/tree_focus/${encodeURIComponent(rest)}/card` },
  // #567: Topic-Eigenschaften-Blade (Pencil im Topic-Blade).
  { kind: "topic_props", prefix: "topicprops:",
    stackId: id => `topicprops:${id}`,
    url: rest => `/topics/${encodeURIComponent(rest)}/properties_card` },
  // #613 Stufe 2: Unterseiten-Blade (settingssub:<page>:<sub>) — VOR
  // settings_page, damit der längere Prefix zuerst matcht.
  { kind: "settings_sub", prefix: "settingssub:",
    stackId: id => `settingssub:${id}`,
    url: rest => {
      const i = rest.indexOf(":")
      const page = rest.slice(0, i), sub = rest.slice(i + 1)
      return `/settings/blade/${encodeURIComponent(page)}/sub/${encodeURIComponent(sub)}`
    } },
  // #618: Inbox-Item-Detail als Blade.
  { kind: "inbox_item", prefix: "inboxitem:",
    stackId: id => `inboxitem:${id}`,
    url: rest => `/inbox/${encodeURIComponent(rest)}/card` },
  // #613: Einstellungs-Seite als Blade (Eintrag im list:settings-Blade).
  { kind: "settings_page", prefix: "settings:",
    stackId: id => `settings:${id}`,
    url: rest => `/settings/blade/${encodeURIComponent(rest)}` },
  { kind: "task", prefix: "task:",
    stackId: id => `task:${id}`,
    url: rest => `/tasks/${encodeURIComponent(rest)}/card` },
  { kind: "source", prefix: "src:",
    stackId: id => `src:${id}`,
    url: rest => `/sources/${encodeURIComponent(rest)}/card` },
  { kind: "awaiting", prefix: "awaiting:",
    stackId: id => `awaiting:${id}`,
    url: rest => `/awaitings/${encodeURIComponent(rest)}/card` },
  { kind: "communication", prefix: "communication:",
    stackId: id => `communication:${id}`,
    url: rest => `/communications/${encodeURIComponent(rest)}/card` },
  // #532: Dokument-Detail-Blade.
  { kind: "document", prefix: "document:",
    stackId: id => `document:${id}`,
    url: rest => `/documents/${encodeURIComponent(rest)}/card` },
  // #541: Rechnungsposition. VOR "invoice:", damit der längere Prefix
  // zuerst matcht.
  { kind: "invoice_line", prefix: "invoiceline:",
    stackId: id => `invoiceline:${id}`,
    url: rest => `/invoice_lines/${encodeURIComponent(rest)}/card` },
  // #926: Rechnung/Angebot als eigene Entität.
  { kind: "invoice", prefix: "invoice:",
    stackId: id => `invoice:${id}`,
    url: rest => `/invoices/${encodeURIComponent(rest)}/card` },
  // #1025 (aus immoos übernommen): PDF-Viewer-Card — id ist
  // base64url("<pfad>\n<titel>") (URL-sichere Zeichen, stabil über Restore).
  { kind: "pdfcard", prefix: "pdfcard:",
    stackId: id => `pdfcard:${id}`,
    url: rest => `/pdf_card/${rest}` },
  // #280: KnowledgeItem — nackte UUID, KEIN Prefix. Muss letzter Eintrag
  // sein (matcht alles); URL kommt aus cardUrlTemplate (Seiten können sie
  // überschreiben) bzw. dessen #563-Default.
  { kind: "ki", prefix: "",
    stackId: id => id,
    url: null }
]

export const BladeStackRoutes = {
  // kind + id (blade-link/Sidebar-Event) → { stackId, url }. null bei
  // unbekanntem kind (Caller warnt — #247: nie still verschlucken).
  forKind(kind, id, { cardUrlTemplate } = {}) {
    const route = ROUTES.find(r => r.kind === kind)
    if (!route) return null
    const stackId = route.stackId(id)
    const url = route.url ? route.url(String(id))
                          : (cardUrlTemplate || "/knowledge_items/UUID/card").replace("UUID", id)
    return { stackId, url }
  },

  // stackId (DOM data-uuid / Restore-Token) → Card-URL. Für nackte
  // KI-UUIDs greift cardUrlTemplate (bzw. dessen Default).
  urlFor(stackId, { cardUrlTemplate } = {}) {
    if (!stackId) return null
    for (const route of ROUTES) {
      if (route.prefix === "") break  // KI-Fallthrough behandelt der Caller-Default unten
      if (stackId.startsWith(route.prefix)) return route.url(stackId.slice(route.prefix.length))
    }
    // UUID (kein Prefix) = KnowledgeItem.
    return (cardUrlTemplate || "/knowledge_items/UUID/card").replace("UUID", stackId)
  }
}
