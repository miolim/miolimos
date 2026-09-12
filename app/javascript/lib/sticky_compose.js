// #1572 (Hans, 2026-09-12): Geometrie des bottom-sticky Antwort-Felds.
// Bewusst als reine Funktionen ohne DOM — so pruefbar mit
// `node --test test/javascript/`, ohne den Umweg ueber
// assets:precompile + System-Test (siehe test/system/README.md).

// Zielhoehe des Editors.
//
//   `fullHeight`   Hoehe, die das Feld mit seinem ganzen Inhalt haette
//   `minHeight`    Untergrenze (in der Regel zwei Zeilen)
//   `anchorBottom` Unterkante des Platzhalters = die Stelle, an der das
//                  voll ausgefahrene Feld enden wuerde (Viewport-Koord.)
//   `viewBottom`   Unterkante des Scroll-Containers (Viewport-Koord.)
//
// Solange der Platz des Felds komplett sichtbar ist, bleibt es voll
// ausgefahren. Scrollt man hoch, schrumpft es um genau den Teil, der
// unter die Kante gerutscht waere — bis zur Untergrenze, danach klebt
// es in dieser Groesse.
export function composeHeight({ fullHeight, minHeight, anchorBottom, viewBottom }) {
  // Nie hoeher machen als der Inhalt: ein Feld mit einer Zeile Text
  // soll nicht auf zwei Zeilen aufgeblasen werden.
  const floor  = Math.min(minHeight, fullHeight)
  const hidden = Math.max(0, anchorBottom - viewBottom)
  return Math.max(floor, fullHeight - hidden)
}

// Ausgleichshoehe des Platzhalters: was das Feld an Hoehe abgibt, muss
// im Fluss stehenbleiben. Sonst wird die Card beim Schrumpfen kuerzer,
// die Scroll-Position verschiebt sich, die naechste Messung ergibt eine
// andere Hoehe — das Feld zittert.
export function spacerHeight({ fullHeight, height }) {
  return Math.max(0, fullHeight - height)
}

// Nach dem Schrumpfen soll der sichtbare Ausschnitt die Cursor-Zeile
// enthalten, nicht die ersten Zeilen des Entwurfs. Liefert den neuen
// scrollTop des Editor-Scrollers.
export function scrollTopForCaret({ caretTop, caretHeight, scrollTop, clientHeight }) {
  const caretBottom = caretTop + caretHeight
  if (caretBottom > scrollTop + clientHeight) return caretBottom - clientHeight
  if (caretTop < scrollTop) return caretTop
  return scrollTop
}
