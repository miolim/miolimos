// Berechnet die Pixel-Position der Cursor-Stelle in einer <textarea>
// (oder <input>) — Trick: wir mirroren die Textarea in einen
// off-screen <div> mit identischen Styling-Eigenschaften, hängen ein
// <span> an der Cursor-Position rein, und lesen dessen
// getBoundingClientRect.
//
// Variante des bekannten "textarea-caret-position"-Pattern (Component),
// minimal eingedampft auf das, was wir brauchen.
//
// Usage:
//   import { caretCoordinates } from "controllers/caret_position"
//   const { top, left, height } = caretCoordinates(textarea)
//   // top/left in viewport-Koordinaten (für position: fixed).

const PROPS = [
  "direction", "boxSizing", "width", "height", "overflowX", "overflowY",
  "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth", "borderStyle",
  "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
  "fontStyle", "fontVariant", "fontWeight", "fontStretch", "fontSize", "fontSizeAdjust", "lineHeight", "fontFamily",
  "textAlign", "textTransform", "textIndent", "textDecoration",
  "letterSpacing", "wordSpacing", "tabSize", "MozTabSize"
]

export function caretCoordinates(element, position = element.selectionEnd) {
  const isInput = element.nodeName === "INPUT"
  const div = document.createElement("div")
  div.id = "caret-mirror"
  document.body.appendChild(div)

  const style = div.style
  const cs    = getComputedStyle(element)

  style.whiteSpace = "pre-wrap"
  if (!isInput) style.wordWrap = "break-word"
  style.position   = "absolute"
  style.visibility = "hidden"

  PROPS.forEach((prop) => { style[prop] = cs[prop] })

  // textarea: keine Scrollbars im Mirror.
  if (isInput) style.overflow = "hidden"
  else         style.overflow = "auto"

  div.textContent = element.value.substring(0, position)
  if (isInput) div.textContent = div.textContent.replace(/\s/g, " ")

  const span = document.createElement("span")
  span.textContent = element.value.substring(position) || "."  // Mindestens 1 Zeichen, damit Span-Box existiert
  div.appendChild(span)

  const rect    = element.getBoundingClientRect()
  const spanBox = span.getBoundingClientRect()
  const divBox  = div.getBoundingClientRect()

  const result = {
    top:    rect.top  + (spanBox.top  - divBox.top)  - element.scrollTop,
    left:   rect.left + (spanBox.left - divBox.left) - element.scrollLeft,
    height: parseInt(cs.lineHeight) || parseInt(cs.fontSize) * 1.2
  }

  document.body.removeChild(div)
  return result
}
