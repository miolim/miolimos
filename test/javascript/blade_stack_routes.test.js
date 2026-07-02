// #801 P3: Unit-Tests für DIE Routing-Tabelle des Blade-Stacks (#564).
// Läuft ohne Build-Step: `node --test test/javascript/` (Node >= 20).
// Die Tabelle ist der Single Point of Truth für Stack-ID ↔ Card-URL —
// ein Drift hier hieß früher: ein Pfad kennt eine Route, der andere nicht.
import { test } from "node:test"
import assert from "node:assert/strict"
import { BladeStackRoutes } from "../../app/javascript/lib/blade_stack_routes.js"

// kind → [id, erwartete stackId, erwartete URL] — deckt jede Zeile der
// Tabelle ab; eine NEUE Blade-Art bekommt hier genau EINEN neuen Eintrag.
const KIND_CASES = [
  ["topic_list",    "demo",        "list:topic:demo",    "/topics/demo/list_card"],
  ["tag_list",      "steuer",      "list:tag:steuer",    "/tags/steuer/list_card"],
  ["list",          "tasks",       "list:tasks",         "/tasks/list_card"],
  ["topic",         "demo",        "topic:demo",         "/topics/demo/card"],
  ["tree_focus",    "42",          "treefocus:42",       "/tree_focus/42/card"],
  ["topic_props",   "demo",        "topicprops:demo",    "/topics/demo/properties_card"],
  ["settings_sub",  "users:7",     "settingssub:users:7","/settings/blade/users/sub/7"],
  ["inbox_item",    "12",          "inboxitem:12",       "/inbox/12/card"],
  ["settings_page", "accounts",    "settings:accounts",  "/settings/blade/accounts"],
  ["task",          "5",           "task:5",             "/tasks/5/card"],
  ["source",        "9",           "src:9",              "/sources/9/card"],
  ["awaiting",      "3",           "awaiting:3",         "/awaitings/3/card"],
  ["communication", "8",           "communication:8",    "/communications/8/card"],
  ["document",      "4",           "document:4",         "/documents/4/card"],
  ["invoice_line",  "6",           "invoiceline:6",      "/invoice_lines/6/card"],
]

test("forKind maps every registered kind to stackId + URL", () => {
  for (const [kind, id, stackId, url] of KIND_CASES) {
    const r = BladeStackRoutes.forKind(kind, id)
    assert.ok(r, `kind ${kind} must be routed`)
    assert.equal(r.stackId, stackId, `stackId for ${kind}`)
    assert.equal(r.url, url, `url for ${kind}`)
  }
})

test("forKind returns null for unknown kinds (caller warns, never swallows)", () => {
  assert.equal(BladeStackRoutes.forKind("gibtsnicht", "1"), null)
})

test("forKind ki uses the default card template and honors overrides", () => {
  const uuid = "0f0e0d0c-1111-2222-3333-444455556666"
  assert.deepEqual(BladeStackRoutes.forKind("ki", uuid),
    { stackId: uuid, url: `/knowledge_items/${uuid}/card` })
  assert.equal(
    BladeStackRoutes.forKind("ki", uuid, { cardUrlTemplate: "/x/UUID/y" }).url,
    `/x/${uuid}/y`)
})

test("urlFor round-trips every prefixed stackId back to the same URL", () => {
  for (const [kind, id, stackId, url] of KIND_CASES) {
    assert.equal(BladeStackRoutes.urlFor(stackId), url,
      `urlFor(${stackId}) must equal forKind(${kind}).url`)
  }
})

test("urlFor resolves longer prefixes before shorter ones", () => {
  // list:topic: und list:tag: müssen VOR list: greifen …
  assert.equal(BladeStackRoutes.urlFor("list:topic:demo"), "/topics/demo/list_card")
  assert.equal(BladeStackRoutes.urlFor("list:tag:x"), "/tags/x/list_card")
  // … und settingssub: vor settings:
  assert.equal(BladeStackRoutes.urlFor("settingssub:users:7"), "/settings/blade/users/sub/7")
})

test("urlFor topic_list with tab suffix appends the tab query", () => {
  assert.equal(BladeStackRoutes.urlFor("list:topic:demo:tasks"),
    "/topics/demo/list_card?tab=tasks")
})

test("urlFor knows the inbox path exception (#618 v2)", () => {
  assert.equal(BladeStackRoutes.urlFor("list:inbox_items"), "/inbox/list_card")
})

test("urlFor URL-encodes ids", () => {
  assert.equal(BladeStackRoutes.urlFor("list:tag:c# code"), "/tags/c%23%20code/list_card")
})

test("urlFor treats bare uuids as KnowledgeItems (template overridable)", () => {
  const uuid = "abcabcab-1111-2222-3333-444455556666"
  assert.equal(BladeStackRoutes.urlFor(uuid), `/knowledge_items/${uuid}/card`)
  assert.equal(BladeStackRoutes.urlFor(uuid, { cardUrlTemplate: "/pub/UUID" }), `/pub/${uuid}`)
  assert.equal(BladeStackRoutes.urlFor(""), null)
  assert.equal(BladeStackRoutes.urlFor(null), null)
})
