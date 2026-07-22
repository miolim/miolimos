// #1114: Autosave-Feedback-Helfer (DOM-arm, ohne Browser testbar).
// Elemente sind hier schlichte Stubs mit getAttribute/querySelectorAll.
import { test } from "node:test"
import assert from "node:assert/strict"
import { isAutosaveTrigger, fieldDescriptor, refindField } from "../../app/javascript/lib/autosave_feedback.js"

const el = (attrs = {}, children = []) => ({
  getAttribute: (k) => (k in attrs ? attrs[k] : null),
  querySelectorAll: (sel) => {
    if (sel === "form")    return children.filter(c => c._tag === "form")
    if (sel === "[name]")  return children.filter(c => c.getAttribute("name") != null)
    return []
  }
})

test("isAutosaveTrigger: erkennt die Inline-requestSubmit-Handler", () => {
  assert.equal(isAutosaveTrigger(el({ onchange: "this.form.requestSubmit()" })), true)
  assert.equal(isAutosaveTrigger(el({ onblur: "if (this.value !== this.defaultValue) this.form.requestSubmit()" })), true)
})

test("isAutosaveTrigger: normale Felder und Nicht-Elemente sind keine Ausloeser", () => {
  assert.equal(isAutosaveTrigger(el({})), false)
  assert.equal(isAutosaveTrigger(el({ onchange: "console.log('x')" })), false)
  assert.equal(isAutosaveTrigger(null), false)
  assert.equal(isAutosaveTrigger({}), false)
})

test("fieldDescriptor: form-action + Feldname, robust gegen fehlende Attribute", () => {
  const form  = el({ action: "/invoices/7" })
  const field = el({ name: "invoice[net_amount]" })
  assert.deepEqual(fieldDescriptor(form, field), { formAction: "/invoices/7", name: "invoice[net_amount]" })
  assert.deepEqual(fieldDescriptor(null, null), { formAction: "", name: "" })
})

test("refindField: findet das Nachfolger-Element nach einem Stream-Replace", () => {
  const successor = { _tag: "input", getAttribute: (k) => (k === "name" ? "invoice[net_amount]" : null) }
  const form  = Object.assign(el({ action: "/invoices/7" }, [successor]), { _tag: "form" })
  const other = Object.assign(el({ action: "/invoices/9" }, []), { _tag: "form" })
  const root  = el({}, [other, form])
  assert.equal(refindField(root, { formAction: "/invoices/7", name: "invoice[net_amount]" }), successor)
})

test("refindField: null bei fremder action, fehlendem Feld oder leerem Namen", () => {
  const form = Object.assign(el({ action: "/invoices/7" }, []), { _tag: "form" })
  const root = el({}, [form])
  assert.equal(refindField(root, { formAction: "/invoices/8", name: "x" }), null)
  assert.equal(refindField(root, { formAction: "/invoices/7", name: "x" }), null)
  assert.equal(refindField(root, { formAction: "/invoices/7", name: "" }), null)
})
