// #1228 (Hans, 2026-07-29): Ueberstand breiter Cards abschneiden.
//
// Im Regal-Zustand (alles nach links weggescrollt) kleben die Cards
// links uebereinander; sichtbar sein soll nur ihr Ruecken plus die
// vorderste Card. Das funktionierte, solange die Cards gleich breit
// waren: jede Card verdeckt die darunterliegende, weil sie hoeher im
// Stapel liegt UND mindestens so breit ist.
//
// Ist eine hintere Card aber BREITER als die vordere, reicht sie rechts
// ueber deren Kante hinaus — und dort verdeckt sie niemand mehr. Sie
// „schaut hinten raus" (Hans' Bild). Der z-Index hilft nicht: er regelt,
// WER oben liegt, nicht WIE WEIT er reicht.
//
// Regel, die das aufloest: Eine Card ist hoechstens bis zur linken Kante
// ihrer Nachfolgerin sichtbar. Wo sie darueber hinausragt, wird sie
// abgeschnitten (clip-path). Im Normalfall — Cards nebeneinander, ohne
// Ueberlappung — endet jede Card ohnehin genau dort, wo die naechste
// beginnt: der Ueberstand ist 0 und es wird nichts geclippt.
//
// Die vorderste Card hat keine Nachfolgerin und wird nie geclippt.

// Subpixel-Rauschen aus getBoundingClientRect (Zoom, fraktionale
// Layouts) soll keinen Clip ausloesen — erst ab einem sichtbaren Rest.
const EPSILON = 0.5

// rects: [{ left, right }, …] in Stapel-Reihenfolge (vorderste zuletzt).
// Rueckgabe: px-Werte fuer den rechten Beschnitt je Card (0 = kein Clip).
export function overhangClips(rects) {
  return rects.map((rect, i) => {
    const next = rects[i + 1]
    if (!next) return 0
    const overhang = rect.right - next.left
    return overhang > EPSILON ? overhang : 0
  })
}
